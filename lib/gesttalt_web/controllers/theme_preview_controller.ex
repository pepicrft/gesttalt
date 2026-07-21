defmodule GesttaltWeb.ThemePreviewController do
  use GesttaltWeb, :controller

  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias Gesttalt.Themes.Renderer

  def home(conn, %{"session_id" => session_id}) do
    with_session(conn, session_id, fn session, site ->
      render_theme(conn, session, fn ->
        Renderer.render_index(
          site,
          session.theme,
          Publishing.list_published_posts(site),
          Publishing.list_published_pages(site)
        )
      end)
    end)
  end

  def article(conn, %{"session_id" => session_id, "slug" => slug}) do
    with_session(conn, session_id, fn session, site ->
      post = Publishing.get_published_post_by_slug!(site, :post, slug)

      render_theme(conn, session, fn ->
        Renderer.render_article(
          site,
          session.theme,
          post,
          Publishing.list_published_pages(site)
        )
      end)
    end)
  end

  def page(conn, %{"session_id" => session_id, "slug" => slug}) do
    with_session(conn, session_id, fn session, site ->
      page = Publishing.get_published_post_by_slug!(site, :page, slug)

      render_theme(conn, session, fn ->
        Renderer.render_page(
          site,
          session.theme,
          page,
          Publishing.list_published_pages(site)
        )
      end)
    end)
  end

  def media(conn, %{"session_id" => session_id, "id" => image_id}) do
    with_session(conn, session_id, fn _session, site ->
      image = Sites.get_image!(site, image_id)

      case Sites.fetch_image(image) do
        {:ok, body} ->
          conn
          |> put_resp_content_type(image.content_type)
          |> put_resp_header("cache-control", "private, no-store")
          |> put_resp_header("referrer-policy", "no-referrer")
          |> send_resp(200, body)

        {:error, _reason} ->
          not_found(conn)
      end
    end)
  end

  def events(conn, %{"session_id" => session_id}) do
    Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session_id))

    case ThemeEditing.fetch(session_id) do
      {:ok, session} ->
        conn =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache, no-store")
          |> put_resp_header("referrer-policy", "no-referrer")
          |> put_resp_header("x-accel-buffering", "no")
          |> send_chunked(200)

        case chunk(conn, "event: ready\ndata: #{session.revision}\n\n") do
          {:ok, conn} -> listen_for_changes(conn)
          {:error, _reason} -> conn
        end

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp listen_for_changes(conn) do
    receive do
      {:theme_editing_session_updated, revision} ->
        case chunk(conn, "event: theme\ndata: #{revision}\n\n") do
          {:ok, conn} -> listen_for_changes(conn)
          {:error, _reason} -> conn
        end

      :theme_editing_session_closed ->
        chunk(conn, "event: closed\ndata: closed\n\n")
        conn
    after
      15_000 ->
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, conn} -> listen_for_changes(conn)
          {:error, _reason} -> conn
        end
    end
  end

  defp with_session(conn, session_id, callback) do
    case ThemeEditing.fetch(session_id) do
      {:ok, session} -> callback.(session, Sites.get_site!(session.site_id))
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp render_theme(conn, session, render) do
    html =
      case render.() do
        {:ok, html} -> html
        {:error, reason} -> render_error(reason)
      end

    html =
      html
      |> rewrite_public_paths(ThemeEditing.preview_path(session.id))
      |> inject_preview_support(session)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> send_resp(200, html)
  end

  defp rewrite_public_paths(html, prefix) do
    html =
      Regex.replace(
        ~r/(\b(?:href|src|action)\s*=\s*["'])\/(?!\/)/i,
        html,
        "\\1#{prefix}/"
      )

    Regex.replace(~r/(url\(\s*["']?)\/(?!\/)/i, html, "\\1#{prefix}/")
  end

  defp inject_preview_support(html, session) do
    support = """
    <meta name="robots" content="noindex, nofollow">
    <script>
      (() => {
        let revision = #{session.revision};
        const changes = new EventSource(#{Jason.encode!(ThemeEditing.preview_path(session.id) <> "/events")});
        const reloadForRevision = event => {
          const nextRevision = Number(event.data);
          if (nextRevision > revision) window.location.reload();
        };
        changes.addEventListener("ready", reloadForRevision);
        changes.addEventListener("theme", reloadForRevision);
      })();
    </script>
    """

    cond do
      String.contains?(html, "</head>") -> String.replace(html, "</head>", support <> "</head>")
      String.contains?(html, "</body>") -> String.replace(html, "</body>", support <> "</body>")
      true -> html <> support
    end
  end

  defp render_error(reason) do
    message = reason |> inspect() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    """
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
      <body><main><h1>Theme preview could not be rendered</h1><pre>#{message}</pre><p>Keep editing. This page will reload after the next theme change.</p></main></body>
    </html>
    """
  end

  defp not_found(conn),
    do: conn |> put_status(:not_found) |> text("Theme editing session not found or expired.")
end
