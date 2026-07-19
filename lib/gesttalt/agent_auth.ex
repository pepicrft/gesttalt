defmodule Gesttalt.AgentAuth do
  @moduledoc """
  Auth.md user-claimed registration and credential exchange for publishing agents.

  Registration secrets and user codes are stored only as SHA-256 digests. State
  transitions are serialized with database row locks and recorded as audit events.
  """

  import Ecto.Query

  alias Boruta.Ecto.AccessTokens
  alias Boruta.Ecto.Admin.Clients
  alias Boruta.Ecto.Client
  alias Boruta.Ecto.OauthMapper
  alias Gesttalt.Accounts.User
  alias Gesttalt.AgentAuth.{Event, Registration}
  alias Gesttalt.OAuth.ResourceOwners
  alias Gesttalt.Repo
  alias Gesttalt.Sites

  @claim_grant "urn:workos:agent-auth:grant-type:claim"
  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @scopes ~w(content:read content:write media:write mcp)
  @client_name "Gesttalt Auth.md"
  @signing_key_term {__MODULE__, :signing_key}

  def claim_grant, do: @claim_grant
  def jwt_bearer_grant, do: @jwt_bearer_grant
  def scopes, do: @scopes
  def poll_interval, do: config()[:poll_interval_seconds] || 5

  def create_service_registration(email, registration_ip) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    with :ok <- validate_email(email),
         :ok <- allow_registration?(registration_ip) do
      create_registration(email, registration_ip)
    end
  end

  def create_service_registration(_email, _registration_ip), do: {:error, :invalid_request}

  defp create_registration(email, registration_ip) do
    claim_token = secret("clm_")
    claim_attempt_token = secret("cla_")
    user_code = user_code()

    attrs = %{
      public_id: secret("reg_"),
      registration_type: :service_auth,
      status: :pending,
      claim_email: email,
      claim_token_hash: digest(claim_token),
      claim_attempt_token_hash: digest(claim_attempt_token),
      user_code_hash: digest(user_code),
      expires_at: DateTime.add(now(), claim_ttl(), :second),
      registration_ip: registration_ip
    }

    Repo.transaction(fn ->
      with {:ok, registration} <- attrs |> Registration.create_changeset() |> Repo.insert(),
           {:ok, _event} <- record_event(registration, "registration.created"),
           {:ok, _event} <-
             record_event(registration, "claim.requested", %{"email" => email}),
           {:ok, _event} <- record_event(registration, "user_code.minted") do
        %{
          registration: registration,
          claim_token: claim_token,
          claim_attempt_token: claim_attempt_token,
          user_code: user_code
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_claim_attempt(claim_attempt_token) when is_binary(claim_attempt_token) do
    Registration
    |> Repo.get_by(claim_attempt_token_hash: digest(claim_attempt_token))
    |> normalize_registration()
  end

  def get_claim_attempt(_claim_attempt_token), do: {:error, :invalid_claim_token}

  def ensure_claim_user(%Registration{} = registration) do
    case Gesttalt.Accounts.get_user_by_email(registration.claim_email) do
      %User{} = user ->
        {:ok, user, :existing}

      nil ->
        case Gesttalt.Accounts.register_user(%{email: registration.claim_email}) do
          {:ok, user} -> {:ok, user, :created}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def confirm_claim(claim_attempt_token, user_code, %User{} = user)
      when is_binary(claim_attempt_token) and is_binary(user_code) do
    Repo.transaction(fn ->
      with {:ok, registration} <- locked_claim_attempt(claim_attempt_token),
           :ok <- ensure_pending(registration),
           :ok <- ensure_same_user(registration, user),
           :ok <- ensure_user_code(registration, user_code),
           {:ok, registration} <-
             registration |> Registration.claim_changeset(user.id, now()) |> Repo.update(),
           {:ok, _site} <- Sites.ensure_site_for_user(user),
           {:ok, _event} <-
             record_event(registration, "claim.confirmed", %{
               "claimed_by_user_id" => user.id
             }) do
        registration
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def confirm_claim(_claim_attempt_token, _user_code, _user), do: {:error, :invalid_request}

  def exchange_claim(claim_token) when is_binary(claim_token) do
    Repo.transaction(fn ->
      with {:ok, registration} <- locked_claim_token(claim_token),
           :ok <- allow_claim_exchange(registration),
           {:ok, response} <- issue_response(registration) do
        {:ok, response}
      else
        {:pending, registration} ->
          registration
          |> Registration.poll_changeset(now())
          |> Repo.update!()

          {:error, :authorization_pending}

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def exchange_claim(_claim_token), do: {:error, :invalid_request}

  def exchange_assertion(assertion, resource \\ nil)

  def exchange_assertion(assertion, resource) when is_binary(assertion) do
    with {:ok, claims} <- verify_assertion(assertion),
         :ok <- validate_resource(resource),
         %Registration{status: :claimed} = registration <-
           Repo.get_by(Registration, public_id: claims["sub"]),
         true <- registration.claimed_by_user_id == claims["user_id"],
         {:ok, token} <- issue_access_token(registration) do
      record_event(registration, "token.issued", %{
        "scope" => Enum.join(@scopes, " "),
        "token_id" => token.id
      })

      {:ok, token_response(token)}
    else
      _error -> {:error, :invalid_grant}
    end
  end

  def exchange_assertion(_assertion, _resource), do: {:error, :invalid_request}

  def revoke_access_token(value) when is_binary(value) do
    case AccessTokens.get_by(value: value) do
      %Boruta.Oauth.Token{client: %{name: @client_name}} = token ->
        with {:ok, _token} <- AccessTokens.revoke(token) do
          record_token_revoked(token)
          :ok
        end

      nil ->
        :ok

      _token ->
        {:error, :not_agent_token}
    end
  end

  def revoke_access_token(_value), do: {:error, :not_agent_token}

  def jwks do
    with {:ok, key} <- signing_key() do
      {_, key_map} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

      {:ok,
       %{
         keys: [
           key_map
           |> Map.put("alg", "RS256")
           |> Map.put("kid", key_id())
           |> Map.put("use", "sig")
         ]
       }}
    end
  end

  defp issue_response(registration) do
    with {:ok, token} <- issue_access_token(registration),
         {:ok, assertion, assertion_expires} <- sign_assertion(registration),
         {:ok, _event} <- record_event(registration, "assertion.issued"),
         {:ok, _event} <-
           record_event(registration, "token.issued", %{
             "scope" => Enum.join(@scopes, " "),
             "token_id" => token.id
           }) do
      {:ok,
       token
       |> token_response()
       |> Map.merge(%{
         identity_assertion: assertion,
         assertion_expires: DateTime.to_iso8601(assertion_expires)
       })}
    end
  end

  defp issue_access_token(%Registration{claimed_by_user_id: user_id}) do
    with {:ok, client_schema} <- agent_client(),
         client <- OauthMapper.to_oauth_schema(client_schema),
         {:ok, owner} <- ResourceOwners.get_by(sub: to_string(user_id)) do
      AccessTokens.create(
        %{
          client: client,
          scope: Enum.join(@scopes, " "),
          sub: to_string(user_id),
          resource: issuer(),
          resource_owner: owner
        },
        refresh_token: false
      )
    end
  end

  defp token_response(token) do
    %{
      access_token: token.value,
      token_type: "Bearer",
      expires_in: max(token.expires_at - System.system_time(:second), 0),
      scope: Enum.join(@scopes, " ")
    }
  end

  defp agent_client do
    case Repo.get_by(Client, name: @client_name) do
      %Client{} = client ->
        {:ok, Repo.preload(client, :authorized_scopes)}

      nil ->
        Clients.create_client(%{
          name: @client_name,
          redirect_uris: [issuer() <> "/agent/identity/claim"],
          supported_grant_types: ["client_credentials", "revoke"],
          token_endpoint_auth_methods: ["client_secret_basic"],
          confidential: true,
          pkce: true,
          public_revoke: true,
          access_token_ttl: 3600,
          authorized_scopes: Enum.map(@scopes, &%{name: &1}),
          metadata: %{"managed_by" => "auth.md"}
        })
    end
  end

  defp sign_assertion(registration) do
    with {:ok, key} <- signing_key(),
         %User{} = user <- Repo.get(User, registration.claimed_by_user_id) do
      issued_at = System.system_time(:second)
      expires_at = issued_at + assertion_ttl()

      claims = %{
        "iss" => issuer(),
        "sub" => registration.public_id,
        "aud" => issuer(),
        "iat" => issued_at,
        "exp" => expires_at,
        "jti" => Ecto.UUID.generate(),
        "user_id" => user.id,
        "email" => user.email,
        "email_verified" => true,
        "scope" => Enum.join(@scopes, " ")
      }

      header = %{"alg" => "RS256", "kid" => key_id(), "typ" => "oauth-id-jag+jwt"}
      {_, assertion} = key |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()

      {:ok, assertion, DateTime.from_unix!(expires_at)}
    else
      _error -> {:error, :signing_key_unavailable}
    end
  end

  defp verify_assertion(assertion) do
    with {:ok, key} <- signing_key(),
         %JOSE.JWS{fields: %{"typ" => "oauth-id-jag+jwt", "kid" => kid}} <-
           JOSE.JWT.peek_protected(assertion),
         true <- kid == key_id(),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           key |> JOSE.JWK.to_public() |> JOSE.JWT.verify_strict(["RS256"], assertion),
         :ok <- validate_assertion_claims(claims) do
      {:ok, claims}
    else
      _error -> {:error, :invalid_grant}
    end
  end

  defp validate_assertion_claims(claims) do
    now = System.system_time(:second)

    if claims["iss"] == issuer() and claims["aud"] == issuer() and
         is_integer(claims["iat"]) and claims["iat"] <= now + 60 and
         is_integer(claims["exp"]) and claims["exp"] > now and
         is_binary(claims["sub"]) and is_integer(claims["user_id"]) do
      :ok
    else
      {:error, :invalid_grant}
    end
  end

  defp signing_key do
    config = config()

    cond do
      pem = config[:private_key_pem] ->
        {:ok, JOSE.JWK.from_pem(pem)}

      config[:allow_ephemeral_signing_key] ->
        {:ok, ephemeral_signing_key()}

      true ->
        {:error, :signing_key_unavailable}
    end
  rescue
    _error -> {:error, :signing_key_unavailable}
  end

  defp ephemeral_signing_key do
    case :persistent_term.get(@signing_key_term, nil) do
      %JOSE.JWK{} = key ->
        key

      nil ->
        key = JOSE.JWK.generate_key({:rsa, 2048})
        :persistent_term.put(@signing_key_term, key)
        key
    end
  end

  defp key_id do
    {:ok, key} = signing_key()
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    public
    |> Jason.encode!()
    |> digest()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  defp locked_claim_attempt(token) do
    Registration
    |> where([registration], registration.claim_attempt_token_hash == ^digest(token))
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> normalize_registration()
  end

  defp locked_claim_token(token) do
    Registration
    |> where([registration], registration.claim_token_hash == ^digest(token))
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> normalize_registration()
  end

  defp normalize_registration(nil), do: {:error, :invalid_claim_token}

  defp normalize_registration(
         %Registration{status: :pending, expires_at: expires_at} = registration
       ) do
    if DateTime.after?(expires_at, now()) do
      {:ok, registration}
    else
      registration |> Registration.expire_changeset() |> Repo.update()
      record_event(registration, "registration.expired")
      {:error, :expired_token}
    end
  end

  defp normalize_registration(%Registration{status: :claimed} = registration),
    do: {:ok, registration}

  defp normalize_registration(%Registration{}), do: {:error, :expired_token}

  defp allow_claim_exchange(%Registration{status: :claimed}), do: :ok

  defp allow_claim_exchange(%Registration{status: :pending} = registration) do
    if polled_too_quickly?(registration),
      do: {:error, :slow_down},
      else: {:pending, registration}
  end

  defp polled_too_quickly?(%Registration{last_polled_at: nil}), do: false

  defp polled_too_quickly?(%Registration{last_polled_at: last_polled_at}) do
    DateTime.diff(now(), last_polled_at, :second) < poll_interval()
  end

  defp ensure_pending(%Registration{status: :pending}), do: :ok
  defp ensure_pending(%Registration{status: :claimed}), do: {:error, :already_claimed}

  defp ensure_same_user(%Registration{claim_email: email}, %User{email: email}), do: :ok
  defp ensure_same_user(_registration, _user), do: {:error, :account_mismatch}

  defp ensure_user_code(registration, code) do
    normalized = code |> String.replace(~r/\D/, "") |> String.trim()
    expected = registration.user_code_hash
    actual = digest(normalized)

    if byte_size(expected) == byte_size(actual) and Plug.Crypto.secure_compare(expected, actual),
      do: :ok,
      else: {:error, :invalid_user_code}
  end

  defp validate_email(email) do
    changeset = User.email_changeset(%User{}, %{email: email}, validate_unique: false)
    if changeset.valid?, do: :ok, else: {:error, :invalid_login_hint}
  end

  defp allow_registration?(nil), do: allow_global_registration?()

  defp allow_registration?(registration_ip) do
    since = DateTime.add(now(), -3600, :second)

    count =
      Repo.aggregate(
        from(registration in Registration,
          where:
            registration.registration_ip == ^registration_ip and
              registration.inserted_at >= ^since
        ),
        :count
      )

    if count < 5, do: allow_global_registration?(), else: {:error, :rate_limited}
  end

  defp allow_global_registration? do
    since = DateTime.add(now(), -3600, :second)

    count =
      Repo.aggregate(
        from(registration in Registration, where: registration.inserted_at >= ^since),
        :count
      )

    if count < 100, do: :ok, else: {:error, :rate_limited}
  end

  defp validate_resource(nil), do: :ok
  defp validate_resource(""), do: :ok

  defp validate_resource(resource) do
    if resource == issuer(), do: :ok, else: {:error, :invalid_target}
  end

  defp record_event(registration, name, metadata \\ %{}) do
    registration |> Event.changeset(name, metadata) |> Repo.insert()
  end

  defp record_token_revoked(token) do
    Event
    |> where(
      [event],
      event.name == "token.issued" and
        fragment("?->>'token_id' = ?", event.metadata, ^token.id)
    )
    |> order_by([event], desc: event.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      %Event{} = event ->
        event.agent_auth_registration_id
        |> then(&Repo.get(Registration, &1))
        |> record_event("token.revoked", %{"token_id" => token.id})

      nil ->
        :ok
    end
  end

  defp config, do: Application.get_env(:gesttalt, :agent_auth, [])
  defp claim_ttl, do: config()[:claim_ttl_seconds] || 600
  defp assertion_ttl, do: config()[:assertion_ttl_seconds] || 86_400
  defp issuer, do: GesttaltWeb.Endpoint.url()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp digest(value), do: :crypto.hash(:sha256, value)

  defp secret(prefix),
    do: prefix <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))

  defp user_code,
    do:
      :crypto.strong_rand_bytes(4)
      |> :binary.decode_unsigned()
      |> rem(1_000_000)
      |> Integer.to_string()
      |> String.pad_leading(6, "0")
end
