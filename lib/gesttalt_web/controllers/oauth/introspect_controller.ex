defmodule GesttaltWeb.OAuth.IntrospectController do
  @behaviour Boruta.Oauth.IntrospectApplication

  use GesttaltWeb, :controller

  alias Boruta.Oauth.{Error, IntrospectResponse}

  def introspect(conn, _params), do: Boruta.Oauth.introspect(conn, __MODULE__)

  @impl true
  def introspect_success(conn, %IntrospectResponse{} = response) do
    response = response |> Map.from_struct() |> Map.drop([:private_key])
    conn |> put_resp_header("cache-control", "no-store") |> json(response)
  end

  @impl true
  def introspect_error(conn, %Error{} = error),
    do:
      conn
      |> put_status(error.status)
      |> json(%{error: error.error, error_description: error.error_description})
end
