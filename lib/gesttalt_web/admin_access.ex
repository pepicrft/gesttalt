defmodule GesttaltWeb.AdminAccess do
  @moduledoc false

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias Gesttalt.Accounts.Scope
  alias Gesttalt.Sites
  alias Gesttalt.Sites.Site
  alias GesttaltWeb.AdminSession

  def init(options), do: options

  def call(conn, _options) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
      |> put_resp_header("x-frame-options", "DENY")

    case {Sites.get_site_by_host(conn.host), Sites.platform_host?(conn.host), current_user(conn)} do
      {%Site{} = site, _platform_host, %{id: user_id}} when site.user_id == user_id ->
        assign(conn, :current_site, site)

      {%Site{}, _platform_host, %{id: _user_id}} ->
        conn |> send_resp(:not_found, "Unknown publication") |> halt()

      {%Site{}, _platform_host, nil} ->
        query = URI.encode_query(%{"return_to" => AdminSession.return_to(conn)})
        conn |> redirect(to: "/admin/session/prepare?#{query}") |> halt()

      {nil, true, %{id: _user_id} = user} ->
        case Sites.ensure_site_for_user(user) do
          {:ok, site} ->
            assign(conn, :current_site, site)

          {:error, _reason} ->
            conn |> send_resp(:service_unavailable, "Publication unavailable") |> halt()
        end

      {nil, true, nil} ->
        conn

      {nil, false, _user} ->
        conn |> send_resp(:not_found, "Unknown publication") |> halt()
    end
  end

  defp current_user(%{assigns: %{current_scope: %Scope{user: user}}}), do: user
  defp current_user(_conn), do: nil
end
