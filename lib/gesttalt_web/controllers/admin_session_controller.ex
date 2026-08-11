defmodule GesttaltWeb.AdminSessionController do
  use GesttaltWeb, :controller

  alias Gesttalt.Accounts
  alias Gesttalt.Accounts.Scope
  alias Gesttalt.Sites
  alias Gesttalt.Sites.Site
  alias GesttaltWeb.{AdminSession, UserAuth}

  def prepare(%{assigns: %{current_site: %Site{}}} = conn, params) do
    state = AdminSession.generate_state()
    return_to = AdminSession.safe_return_to(params["return_to"])

    conn
    |> put_session(:admin_handoff_state, state)
    |> put_resp_header("cache-control", "private, no-store")
    |> redirect(external: AdminSession.platform_start_url(conn.host, state, return_to))
  end

  def prepare(conn, _params), do: send_resp(conn, :not_found, "Unknown publication")

  def start(conn, params) do
    if Sites.platform_host?(conn.host) do
      start_from_platform(conn, params)
    else
      send_resp(conn, :not_found, "Unknown publication")
    end
  end

  def complete(%{assigns: %{current_site: %Site{} = site}} = conn, %{"token" => token} = params) do
    state = get_session(conn, :admin_handoff_state)
    return_to = AdminSession.safe_return_to(params["return_to"])

    with true <- AdminSession.valid_state?(state),
         {:ok, user} <- Accounts.consume_admin_handoff_token(token, conn.host, state),
         true <- user.id == site.user_id do
      conn
      |> delete_session(:admin_handoff_state)
      |> put_session(:user_return_to, return_to)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> UserAuth.log_in_user(user)
    else
      _reason ->
        conn
        |> delete_session(:admin_handoff_state)
        |> send_resp(:unauthorized, "Admin sign-in could not be completed")
    end
  end

  def complete(conn, _params), do: send_resp(conn, :not_found, "Unknown publication")

  defp start_from_platform(%{assigns: %{current_scope: %Scope{user: user}}} = conn, params)
       when not is_nil(user) do
    with %{} = domain <- Sites.get_active_domain_by_host(params["host"] || ""),
         true <- domain.site.user_id == user.id,
         true <- AdminSession.valid_state?(params["state"]),
         {:ok, token} <-
           Accounts.generate_admin_handoff_token(user, domain.hostname, params["state"]) do
      return_to = AdminSession.safe_return_to(params["return_to"])

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> redirect(external: AdminSession.completion_url(domain.hostname, token, return_to))
    else
      _reason -> send_resp(conn, :not_found, "Unknown publication")
    end
  end

  defp start_from_platform(conn, _params), do: UserAuth.require_authenticated_user(conn, [])
end
