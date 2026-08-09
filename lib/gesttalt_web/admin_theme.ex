defmodule GesttaltWeb.AdminTheme do
  @moduledoc false

  import Plug.Conn

  alias Gesttalt.Sites

  def init(options), do: options

  def call(conn, _options) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    assign(conn, :admin_theme, Sites.get_theme!(site))
  end
end
