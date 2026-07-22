defmodule GesttaltWeb.OAuth.RegistrationController do
  @behaviour Boruta.Openid.DynamicRegistrationApplication

  use GesttaltWeb, :controller

  import Ecto.Changeset, only: [traverse_errors: 2]

  alias Boruta.Oauth.Client

  @default_grant_types ["authorization_code", "refresh_token"]
  @default_response_types ["code"]
  @public_auth_method "none"

  @key_map %{
    "client_name" => :client_name,
    "name" => :name,
    "redirect_uris" => :redirect_uris,
    "grant_types" => :supported_grant_types,
    "response_types" => :response_types,
    "token_endpoint_auth_method" => :token_endpoint_auth_method,
    "jwks" => :jwks,
    "jwks_uri" => :jwks_uri,
    "metadata" => :metadata
  }

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
    params
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, Map.get(@key_map, key, key), value)
    end)
    |> Map.put_new(:supported_grant_types, @default_grant_types)
    |> Map.put_new(:response_types, @default_response_types)
    |> Map.put_new(:token_endpoint_auth_method, @public_auth_method)
    |> Map.put_new(
      :authorized_scopes,
      Enum.map(GesttaltWeb.WellKnownController.scopes(), &%{name: &1})
    )
    |> preserve_response_types()
    |> normalize_public_client()
  end

  defp preserve_response_types(params) do
    metadata =
      Map.put(Map.get(params, :metadata, %{}), "response_types", params.response_types)

    Map.put(params, :metadata, metadata)
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
  defp auth_method(%Client{metadata: %{"token_endpoint_auth_method" => method}}), do: method
  defp auth_method(%Client{token_endpoint_auth_methods: [method | _]}), do: method
  defp auth_method(_client), do: nil

  defp response_types(%Client{metadata: %{"response_types" => response_types}}),
    do: response_types

  defp response_types(_client), do: @default_response_types
end
