defmodule GesttaltWeb.OAuthAuth do
  @moduledoc "Authenticates publishing requests with a valid OAuth 2.0 bearer access token."

  import Plug.Conn

  alias Boruta.Oauth.Authorization.AccessToken
  alias Boruta.Oauth.Scope
  alias Gesttalt.Accounts.User
  alias Gesttalt.Repo
  alias Gesttalt.Sites

  def init(opts), do: opts

  def call(conn, opts) do
    required_scopes = Keyword.get(opts, :scopes, [])

    with {:ok, value} <- bearer_token(conn),
         {:ok, token} <- AccessToken.authorize(value: value),
         %User{} = user <- Repo.get(User, token.sub),
         {:ok, site} <- Sites.ensure_site_for_user(user),
         :ok <- authorize_scopes(token.scope, required_scopes) do
      conn
      |> assign(:oauth_token, token)
      |> assign(:current_user, user)
      |> assign(:current_site, site)
    else
      {:error, :insufficient_scope} -> unauthorized(conn, "insufficient_scope", required_scopes)
      _error -> unauthorized(conn, "invalid_token", required_scopes)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _other -> {:error, :missing_token}
    end
  end

  defp authorize_scopes(scope, required) do
    granted = MapSet.new(Scope.split(scope))

    if Enum.all?(required, &MapSet.member?(granted, &1)),
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp unauthorized(conn, error, scopes) do
    metadata_path =
      if conn.request_path == "/mcp",
        do: "/.well-known/oauth-protected-resource/mcp",
        else: "/.well-known/oauth-protected-resource"

    metadata = GesttaltWeb.Endpoint.url() <> metadata_path
    scope = Enum.join(scopes, " ")

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer resource_metadata="#{metadata}", error="#{error}", scope="#{scope}")
    )
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: error}))
    |> halt()
  end
end
