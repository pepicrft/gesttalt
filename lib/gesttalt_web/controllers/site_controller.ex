defmodule GesttaltWeb.SiteController do
  use GesttaltWeb, :controller

  alias Gesttalt.Photography
  alias Gesttalt.PublicMarkdown
  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.Themes.Renderer

  @owner_controls """
  <style id="gesttalt-owner-controls-style">
    #gesttalt-owner-controls {
      position: fixed;
      right: 1rem;
      bottom: 1rem;
      z-index: 2147483647;
      font: 600 0.875rem/1 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    #gesttalt-owner-controls a {
      display: inline-flex;
      align-items: center;
      min-height: 2.5rem;
      padding: 0.75rem 1rem;
      border: 1px solid rgb(255 255 255 / 18%);
      border-radius: 999px;
      background: #171717;
      box-shadow: 0 0.25rem 1rem rgb(0 0 0 / 20%);
      color: #fff;
      text-decoration: none;
    }

    #gesttalt-owner-controls a:hover {
      background: #303030;
      color: #fff;
    }

    #gesttalt-owner-controls a:focus-visible {
      outline: 3px solid #7db6ff;
      outline-offset: 3px;
    }
  </style>
  <aside id="gesttalt-owner-controls" aria-label="Publication controls">
    <a href="/admin/">Dashboard</a>
  </aside>
  """

  def home(%{assigns: %{current_site: nil}} = conn, params),
    do: conn |> put_view(html: GesttaltWeb.PageHTML) |> GesttaltWeb.PageController.home(params)

  def home(%{assigns: %{current_site: site}} = conn, _params) do
    posts = Publishing.list_recent_published_posts(site)

    if markdown_requested?(conn) do
      markdown(conn, PublicMarkdown.home(site, posts))
    else
      og = og_context(conn, site)

      render_theme(conn, site, fn ->
        Renderer.render_index(
          site,
          site.theme,
          posts,
          Publishing.list_published_pages(site),
          nil,
          og
        )
      end)
    end
  end

  def archive(%{assigns: %{current_site: site}} = conn, params) do
    page = page_number(params)
    {posts, pagination} = Publishing.paginate_published_posts(site, page)
    last_page = max(pagination.total_pages, 1)

    if page > last_page do
      redirect(conn, to: archive_path(last_page))
    else
      render_archive(conn, site, posts, pagination)
    end
  end

  def archive_markdown(%{assigns: %{current_site: site}} = conn, params) do
    page = page_number(params)
    {posts, pagination} = Publishing.paginate_published_posts(site, page)
    last_page = max(pagination.total_pages, 1)

    if page > last_page do
      redirect(conn, to: archive_markdown_path(last_page))
    else
      markdown(conn, PublicMarkdown.archive(site, posts, pagination))
    end
  end

  defp render_archive(conn, site, posts, pagination) do
    if markdown_requested?(conn) do
      markdown(conn, PublicMarkdown.archive(site, posts, pagination))
    else
      og = og_context(conn, site)

      render_theme(conn, site, fn ->
        Renderer.render_index(
          site,
          site.theme,
          posts,
          Publishing.list_published_pages(site),
          pagination,
          og,
          archive: true,
          archive_path: "/blog"
        )
      end)
    end
  end

  def article(%{assigns: %{current_site: site}} = conn, %{"slug" => slug}) do
    {slug, markdown?} = markdown_path?(slug, conn)
    post = Publishing.get_published_post_by_slug!(site, :post, slug)

    if markdown? do
      markdown(conn, PublicMarkdown.article(post))
    else
      og = og_context(conn, site)

      render_theme(conn, site, fn ->
        Renderer.render_article(site, site.theme, post, Publishing.list_published_pages(site), og)
      end)
    end
  end

  def page(%{assigns: %{current_site: site}} = conn, %{"slug" => slug}) do
    {slug, markdown?} = markdown_path?(slug, conn)
    page = Publishing.get_published_post_by_slug!(site, :page, slug)

    if markdown? do
      markdown(conn, PublicMarkdown.page(page))
    else
      og = og_context(conn, site)

      render_theme(conn, site, fn ->
        Renderer.render_page(site, site.theme, page, Publishing.list_published_pages(site), og)
      end)
    end
  end

  def photography(%{assigns: %{current_site: nil}} = conn, _params),
    do: conn |> put_status(:not_found) |> text("Photography feed not found")

  def photography(%{assigns: %{current_site: site}} = conn, _params) do
    photos = Photography.list_published_photos(site)

    if markdown_requested?(conn) do
      markdown(conn, PublicMarkdown.photography(site, photos))
    else
      og = og_context(conn, site)

      render_theme(conn, site, fn ->
        Renderer.render_photography(
          site,
          site.theme,
          photos,
          Publishing.list_published_pages(site),
          og
        )
      end)
    end
  end

  def photography_markdown(%{assigns: %{current_site: site}} = conn, _params) do
    markdown(conn, PublicMarkdown.photography(site, Photography.list_published_photos(site)))
  end

  def home_markdown(%{assigns: %{current_site: site}} = conn, _params) do
    markdown(conn, PublicMarkdown.home(site, Publishing.list_recent_published_posts(site)))
  end

  def llms(%{assigns: %{current_site: site}} = conn, _params) do
    markdown(
      conn,
      PublicMarkdown.index(
        site,
        Publishing.list_published_pages(site),
        Publishing.list_published_posts(site)
      )
    )
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

  defp markdown_requested?(conn), do: get_format(conn) == "md"

  defp markdown_path?(slug, conn) do
    case String.trim_trailing(slug, ".md") do
      ^slug -> {slug, markdown_requested?(conn)}
      "" -> {slug, markdown_requested?(conn)}
      markdown_slug -> {markdown_slug, true}
    end
  end

  defp markdown(conn, document) do
    conn
    |> put_resp_header("vary", "accept")
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
  end

  defp og_context(conn, site) do
    %{site: site, theme: site.theme, base_url: og_base_url(conn)}
  end

  defp og_base_url(conn) do
    scheme = endpoint_scheme()

    case conn.port do
      port when port in [80, 443] or is_nil(port) -> "#{scheme}://#{conn.host}"
      port -> "#{scheme}://#{conn.host}:#{port}"
    end
  end

  defp endpoint_scheme do
    :gesttalt
    |> Application.get_env(GesttaltWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:scheme, "https")
  end

  defp render_theme(conn, site, render) do
    case render.() do
      {:ok, html} ->
        {conn, html} = maybe_add_owner_controls(conn, html, site)

        conn
        |> put_resp_header("vary", "accept, cookie")
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("Theme could not be rendered: #{inspect(reason)}")
    end
  end

  defp maybe_add_owner_controls(conn, html, site) do
    if owner?(conn, site) do
      conn = put_resp_header(conn, "cache-control", "private, no-store")
      {conn, inject_before_body_end(html, @owner_controls)}
    else
      {conn, html}
    end
  end

  defp owner?(conn, site) do
    case conn.assigns.current_scope do
      %{user: %{id: user_id}} -> user_id == site.user_id
      _scope -> false
    end
  end

  defp inject_before_body_end(html, controls) do
    case Regex.run(~r/<\/body\s*>/i, html, return: :index) do
      [{position, _length}] ->
        before_body_end = binary_part(html, 0, position)
        body_end = binary_part(html, position, byte_size(html) - position)
        before_body_end <> controls <> body_end

      :nomatch ->
        html <> controls
    end
  end

  defp page_number(%{"page" => value}) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page in 1..1_000_000 -> page
      _invalid -> 1
    end
  end

  defp page_number(_params), do: 1

  defp archive_path(1), do: "/blog"
  defp archive_path(page), do: "/blog?page=#{page}"

  defp archive_markdown_path(1), do: "/blog.md"
  defp archive_markdown_path(page), do: "/blog.md?page=#{page}"
end
