defmodule GesttaltWeb.DomainAllowController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites

  def show(conn, %{"domain" => domain}) do
    if Sites.platform_host?(domain) or Sites.get_site_by_host(domain) do
      send_resp(conn, :ok, "allowed")
    else
      send_resp(conn, :not_found, "unknown domain")
    end
  end

  def show(conn, _params), do: send_resp(conn, :bad_request, "domain is required")
end
