defmodule Gesttalt.OAuth.Clients do
  @moduledoc "Boruta client adapter backed by PostgreSQL, including dynamically registered clients."

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  alias Boruta.Ecto.Clients

  @impl true
  defdelegate get_client(id), to: Clients

  @impl true
  defdelegate get_client_by_did(did), to: Clients

  @impl true
  defdelegate public!(), to: Clients

  @impl true
  defdelegate authorized_scopes(client), to: Clients

  @impl true
  defdelegate list_clients_jwk(), to: Clients

  @impl true
  defdelegate create_client(params), to: Clients

  @impl true
  defdelegate refresh_jwk_from_jwks_uri(client_id), to: Clients
end
