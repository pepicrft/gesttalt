defmodule GesttaltWeb.ThemeController do
  use GesttaltWeb, :controller

  alias Gesttalt.Sites
  alias Gesttalt.Sites.ThemeDefaults

  def edit(conn, _params) do
    site = current_site(conn)
    theme = Sites.get_theme!(site)

    render(conn, :edit,
      page_title: "Theme",
      built_in_themes: ThemeDefaults.all(),
      active_built_in_theme:
        if(theme.inherited, do: theme.built_in_theme || ThemeDefaults.default_id()),
      site: site,
      theme: theme
    )
  end

  def select(conn, %{"built_in_theme" => built_in_theme}) do
    site = current_site(conn)

    case Sites.select_built_in_theme(site, built_in_theme) do
      {:ok, _theme} ->
        conn
        |> put_flash(
          :info,
          "Theme selected. It will keep receiving built-in updates until you customize it."
        )
        |> redirect(to: ~p"/admin/theme")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That theme is not available.")
        |> redirect(to: ~p"/admin/theme")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "The theme could not be selected.")
        |> redirect(to: ~p"/admin/theme")
    end
  end

  defp current_site(conn) do
    {:ok, site} = Sites.ensure_site_for_user(conn.assigns.current_scope.user)
    site
  end
end
