defmodule GesttaltWeb.OAuth.RevokeController do
  @behaviour Boruta.Oauth.RevokeApplication

  use GesttaltWeb, :controller

  alias Boruta.Oauth.Error
  alias Gesttalt.AgentAuth

  def revoke(conn, %{"token" => token}) do
    case AgentAuth.revoke_access_token(token) do
      :ok -> revoke_success(conn)
      {:error, :not_agent_token} -> Boruta.Oauth.revoke(conn, __MODULE__)
    end
  end

  def revoke(conn, _params), do: Boruta.Oauth.revoke(conn, __MODULE__)

  @impl true
  def revoke_success(conn), do: send_resp(conn, :ok, "")

  @impl true
  def revoke_error(conn, %Error{} = error),
    do:
      conn
      |> put_status(error.status)
      |> json(%{error: error.error, error_description: error.error_description})
end
