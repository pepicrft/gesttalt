defmodule GesttaltWeb.AgentIdentityController do
  use GesttaltWeb, :controller

  alias Gesttalt.AgentAuth
  alias GesttaltWeb.ClientAddress

  def create(conn, %{"type" => "service_auth", "login_hint" => email}) do
    case AgentAuth.create_service_registration(email, ClientAddress.from_conn(conn)) do
      {:ok,
       %{
         registration: registration,
         claim_token: claim_token,
         claim_attempt_token: claim_attempt_token,
         user_code: user_code
       }} ->
        json(
          conn,
          registration_response(
            registration,
            claim_token,
            claim_attempt_token,
            user_code
          )
        )

      {:error, reason} ->
        identity_error(conn, reason)
    end
  end

  def create(conn, %{"type" => "anonymous"}), do: identity_error(conn, :anonymous_not_enabled)

  def create(conn, %{"type" => "identity_assertion"}),
    do: identity_error(conn, :issuer_not_enabled)

  def create(conn, _params), do: identity_error(conn, :invalid_request)

  def claim(conn, %{"claim_token" => claim_token, "email" => email}) do
    case AgentAuth.renew_service_claim(claim_token, email) do
      {:ok,
       %{
         registration: registration,
         claim_attempt_token: claim_attempt_token,
         user_code: user_code
       }} ->
        conn
        |> json(%{
          registration_id: registration.public_id,
          claim_attempt_id: claim_attempt_id(claim_attempt_token),
          status: "initiated",
          expires_at: DateTime.to_iso8601(registration.claim_attempt_expires_at),
          claim_attempt: claim_details(registration, claim_attempt_token, user_code)
        })

      {:error, reason} ->
        claim_error(conn, reason)
    end
  end

  def claim(conn, _params), do: claim_error(conn, :invalid_request)

  defp identity_error(conn, :rate_limited) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", "3600")
    |> json(%{error: "rate_limited", error_description: "Try registering again later."})
  end

  defp identity_error(conn, :invalid_login_hint) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "invalid_request",
      error_description: "A valid email login_hint is required."
    })
  end

  defp identity_error(conn, :anonymous_not_enabled) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "anonymous_not_enabled",
      error_description:
        "Gesttalt requires a user email and does not accept anonymous registration."
    })
  end

  defp identity_error(conn, :issuer_not_enabled) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "issuer_not_enabled",
      error_description: "Gesttalt does not currently trust external identity assertion issuers."
    })
  end

  defp identity_error(conn, _reason),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "invalid_request",
        error_description: "Use the service_auth identity type."
      })

  defp claim_error(conn, reason) do
    {status, error, description} =
      case reason do
        :claim_expired ->
          {:gone, "claim_expired", "The registration has expired. Start registration again."}

        :already_claimed ->
          {:conflict, "claimed_or_in_flight", "This registration has already been claimed."}

        :invalid_claim_token ->
          {:bad_request, "invalid_claim_token", "The claim token or email is invalid."}

        _reason ->
          {:bad_request, "invalid_request", "A claim token and matching email are required."}
      end

    conn |> put_status(status) |> json(%{error: error, error_description: description})
  end

  defp registration_response(registration, claim_token, claim_attempt_token, user_code) do
    %{
      registration_id: registration.public_id,
      registration_type: "service_auth",
      claim_url: url(~p"/agent/identity/claim"),
      claim_token: claim_token,
      claim_token_expires: DateTime.to_iso8601(registration.expires_at),
      post_claim_scopes: AgentAuth.scopes(),
      claim: claim_details(registration, claim_attempt_token, user_code)
    }
  end

  defp claim_details(registration, claim_attempt_token, user_code) do
    expires_in =
      DateTime.diff(registration.claim_attempt_expires_at, DateTime.utc_now(), :second)

    %{
      user_code: user_code,
      expires_in: max(expires_in, 0),
      verification_uri: url(~p"/agent/identity/claim?claim_attempt_token=#{claim_attempt_token}"),
      interval: AgentAuth.poll_interval()
    }
  end

  defp claim_attempt_id(claim_attempt_token) do
    "cla_" <>
      (:crypto.hash(:sha256, claim_attempt_token)
       |> Base.url_encode64(padding: false)
       |> binary_part(0, 24))
  end
end
