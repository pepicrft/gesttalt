defmodule GesttaltWeb.OAuth.AuthorizeController do
  @behaviour Boruta.Oauth.AuthorizeApplication

  use GesttaltWeb, :controller

  alias Boruta.Oauth.{AuthorizeResponse, Error, ResourceOwner}

  @max_state_length 10_000

  def authorize(%Plug.Conn{assigns: %{current_scope: %{user: user}}} = conn, params)
      when not is_nil(user) do
    if byte_size(params["state"] || "") <= @max_state_length do
      Boruta.Oauth.authorize(
        default_scope(conn),
        %ResourceOwner{sub: to_string(user.id), username: user.email},
        __MODULE__
      )
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "invalid_request", error_description: "The state parameter is too long."})
    end
  end

  def authorize(conn, _params) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect(to: ~p"/users/log-in")
    |> halt()
  end

  # Some Model Context Protocol clients omit the scope parameter. Without a scope,
  # Boruta issues a token that cannot call any protected endpoint, so grant only the
  # Model Context Protocol scope. Request objects carry their own scope, which Boruta
  # merges under the query parameters, so a default here would override it.
  defp default_scope(%Plug.Conn{query_params: %{"request" => _request}} = conn), do: conn
  defp default_scope(%Plug.Conn{query_params: %{"request_uri" => _uri}} = conn), do: conn

  defp default_scope(%Plug.Conn{query_params: params} = conn) do
    case String.trim(params["scope"] || "") do
      "" ->
        %{conn | query_params: Map.put(params, "scope", "mcp")}

      _scope ->
        conn
    end
  end

  @impl true
  def authorize_success(conn, %AuthorizeResponse{} = response),
    do: redirect(conn, external: AuthorizeResponse.redirect_to_url(response))

  @impl true
  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format),
    do: redirect(conn, external: Error.redirect_to_url(error))

  def authorize_error(conn, %Error{} = error) do
    conn
    |> put_status(error.status)
    |> json(%{error: to_string(error.error), error_description: error.error_description})
  end

  @impl true
  def preauthorize_success(_conn, _response), do: :ok

  @impl true
  def preauthorize_error(_conn, _response), do: :ok
end
