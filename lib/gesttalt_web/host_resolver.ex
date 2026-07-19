defmodule GesttaltWeb.HostResolver do
  @moduledoc "Resolves the request host to an active tenant without trusting a caller-provided site identifier."

  import Plug.Conn

  alias Gesttalt.Sites

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      site = Sites.get_site_by_host(conn.host) -> assign(conn, :current_site, site)
      Sites.platform_host?(conn.host) -> assign(conn, :current_site, nil)
      true -> conn |> send_resp(404, "Unknown publication") |> halt()
    end
  end
end
