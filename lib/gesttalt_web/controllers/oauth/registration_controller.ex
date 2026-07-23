defmodule GesttaltWeb.OAuth.RegistrationController do
  @behaviour Boruta.Openid.DynamicRegistrationApplication

  use GesttaltWeb, :controller

  import Ecto.Changeset, only: [traverse_errors: 2]

  alias Boruta.Oauth.Client

  @default_grant_types ["authorization_code", "refresh_token"]
  @default_response_types ["code"]
  @interactive_grant_types ["authorization_code", "refresh_token"]
  @public_auth_method "none"
  @registration_metadata_keys ~w(client_uri contacts policy_uri scope software_id software_version tos_uri)

  def register(conn, params),
    do: Boruta.Openid.register_client(conn, normalize(params), __MODULE__)

  @impl true
  def client_registered(conn, %Client{} = client) do
    response = %{
      client_id: client.id,
      client_id_issued_at: DateTime.utc_now() |> DateTime.to_unix(),
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      grant_types: client.supported_grant_types,
      response_types: response_types(client),
      token_endpoint_auth_method: auth_method(client)
    }

    response =
      if client.confidential do
        Map.merge(response, %{client_secret: client.secret, client_secret_expires_at: 0})
      else
        response
      end

    conn
    |> put_status(:created)
    |> json(response)
  end

  @impl true
  def registration_failure(conn, changeset) do
    errors =
      changeset
      |> traverse_errors(fn {message, _opts} -> message end)
      |> Enum.map_join(" ", fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)

    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_client_metadata", error_description: errors})
  end

  defp normalize(params) do
    response_types = requested_response_types(params)
    auth_method = Map.get(params, "token_endpoint_auth_method", @public_auth_method)

    %{
      name: Map.get(params, "client_name") || Map.get(params, "name") || "Dynamic client",
      redirect_uris: Map.get(params, "redirect_uris", []),
      supported_grant_types: grant_types(params),
      authorized_scopes: Enum.map(GesttaltWeb.WellKnownController.scopes(), &%{name: &1}),
      response_types: response_types,
      token_endpoint_auth_method: auth_method,
      metadata: registration_metadata(params, response_types, auth_method)
    }
    |> maybe_put(:jwks, Map.get(params, "jwks"))
    |> maybe_put(:jwks_uri, Map.get(params, "jwks_uri"))
    |> normalize_public_client()
  end

  defp grant_types(params) do
    case Map.get(params, "grant_types", @default_grant_types) do
      grant_types when is_list(grant_types) ->
        supported = Enum.filter(grant_types, &(&1 in @interactive_grant_types))

        if supported == [], do: grant_types, else: supported

      _grant_types ->
        @default_grant_types
    end
  end

  defp requested_response_types(params) do
    case Map.get(params, "response_types", @default_response_types) do
      response_types when is_list(response_types) ->
        supported = Enum.filter(response_types, &(&1 in @default_response_types))

        if supported == [], do: @default_response_types, else: supported

      _response_types ->
        @default_response_types
    end
  end

  defp registration_metadata(params, response_types, auth_method) do
    metadata = if is_map(params["metadata"]), do: params["metadata"], else: %{}

    metadata =
      params
      |> Map.take(@registration_metadata_keys)
      |> Map.merge(metadata)

    metadata
    |> Map.put("response_types", response_types)
    |> Map.put("token_endpoint_auth_method", auth_method)
  end

  defp normalize_public_client(%{token_endpoint_auth_method: @public_auth_method} = params) do
    metadata =
      Map.put(Map.get(params, :metadata, %{}), "token_endpoint_auth_method", @public_auth_method)

    params
    |> Map.delete(:token_endpoint_auth_method)
    |> Map.merge(%{
      metadata: metadata,
      confidential: false,
      pkce: true,
      public_refresh_token: true,
      public_revoke: true
    })
  end

  defp normalize_public_client(%{token_endpoint_auth_method: method} = params)
       when method in ["client_secret_basic", "client_secret_post"],
       do: Map.put(params, :confidential, true)

  defp normalize_public_client(params), do: params
  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp auth_method(%Client{metadata: %{"token_endpoint_auth_method" => method}}), do: method
  defp auth_method(%Client{token_endpoint_auth_methods: [method | _]}), do: method
  defp auth_method(_client), do: nil

  defp response_types(%Client{metadata: %{"response_types" => response_types}}),
    do: response_types

  defp response_types(_client), do: @default_response_types
end
