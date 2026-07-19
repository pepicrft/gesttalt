defmodule GesttaltWeb.ThemeController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites

  def edit(conn, _params) do
    site = current_site(conn)
    theme = Sites.get_theme!(site)

    render(conn, :edit,
      page_title: "Theme",
      site: site,
      theme: theme
    )
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
