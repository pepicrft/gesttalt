defmodule Gesttalt.OAuth.ClientsManager do
  @moduledoc "Account-scoped management of OAuth 2.0 clients created in the dashboard."

  import Ecto.Query

  alias Boruta.Ecto.Admin.Clients
  alias Boruta.Ecto.Client
  alias Gesttalt.Accounts.User
  alias Gesttalt.Repo

  @scopes ~w(content:read content:write media:write mcp)

  def list_clients(%User{id: user_id}) do
    owner_id = to_string(user_id)

    Client
    |> where([client], fragment("?->>'owner_user_id'", client.metadata) == ^owner_id)
    |> order_by([client], desc: client.inserted_at)
    |> Repo.all()
  end

  def create_client(%User{} = user, attrs) do
    name = value(attrs, :name)

    params = %{
      name: name,
      redirect_uris: parse_redirect_uris(value(attrs, :redirect_uris)),
      supported_grant_types: ["authorization_code", "refresh_token", "revoke"],
      token_endpoint_auth_methods: ["client_secret_basic", "client_secret_post"],
      confidential: truthy?(value(attrs, :confidential)),
      pkce: true,
      public_refresh_token: true,
      public_revoke: true,
      authorized_scopes: Enum.map(@scopes, &%{name: &1}),
      metadata: %{"owner_user_id" => to_string(user.id)}
    }

    Clients.create_client(params)
  end

  def delete_client(%User{} = user, id) do
    case Enum.find(list_clients(user), &(&1.id == id)) do
      %Client{} = client -> Clients.delete_client(client)
      nil -> {:error, :not_found}
    end
  end

  defp parse_redirect_uris(value) when is_binary(value) do
    value |> String.split(~r/[\n,]+/, trim: true) |> Enum.map(&String.trim/1)
  end

  defp parse_redirect_uris(value) when is_list(value), do: value
  defp parse_redirect_uris(_value), do: []
  defp truthy?(value), do: value in [true, "true", "1", "on"]
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
