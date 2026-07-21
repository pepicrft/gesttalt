defmodule GesttaltWeb.SiteController do
  use GesttaltWeb, :controller

  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.Themes.Renderer

  def home(%{assigns: %{current_site: nil}} = conn, params),
    do: conn |> put_view(html: GesttaltWeb.PageHTML) |> GesttaltWeb.PageController.home(params)

  def home(%{assigns: %{current_site: site}} = conn, _params) do
    render_theme(conn, fn ->
      Renderer.render_index(
        site,
        site.theme,
        Publishing.list_published_posts(site),
        Publishing.list_published_pages(site)
      )
    end)
  end

  def article(%{assigns: %{current_site: site}} = conn, %{"slug" => slug}) do
    post = Publishing.get_published_post_by_slug!(site, :post, slug)

    render_theme(conn, fn ->
      Renderer.render_article(site, site.theme, post, Publishing.list_published_pages(site))
    end)
  end

  def page(%{assigns: %{current_site: site}} = conn, %{"slug" => slug}) do
    page = Publishing.get_published_post_by_slug!(site, :page, slug)

    render_theme(conn, fn ->
      Renderer.render_page(site, site.theme, page, Publishing.list_published_pages(site))
    end)
  end

  def media(%{assigns: %{current_site: site}} = conn, %{"id" => id}) do
    image = Sites.get_image!(site, id)
    send_media(conn, image, "public, max-age=31536000, immutable")
  end

  defp send_media(conn, image, cache_control) do
    case Sites.fetch_image(image) do
      {:ok, body} ->
        conn
        |> put_resp_content_type(image.content_type)
        |> put_resp_header("cache-control", cache_control)
        |> send_resp(200, body)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Media not found")

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> text("Media could not be loaded: #{inspect(reason)}")
    end
  end

  defp render_theme(conn, render) do
    case render.() do
      {:ok, html} ->
        conn |> put_resp_content_type("text/html") |> send_resp(200, html)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("Theme could not be rendered: #{inspect(reason)}")
    end
  end
end
