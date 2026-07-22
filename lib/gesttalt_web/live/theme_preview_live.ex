defmodule GesttaltWeb.ThemePreviewLive do
  use GesttaltWeb, :live_view

  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias Gesttalt.Themes.Renderer

  @impl true
  def mount(
        _params,
        %{"page" => page, "session_id" => session_id, "site_id" => site_id},
        socket
      ) do
    site = Sites.get_site!(site_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session_id))
    end

    socket =
      socket
      |> assign(:page, page)
      |> assign(:page_title, "Theme preview · #{site.name}")
      |> assign(:session_id, session_id)
      |> assign(:site, site)

    case ThemeEditing.fetch(session_id) do
      {:ok, session} -> {:ok, show_theme(socket, session.theme, session.revision, :editing)}
      {:error, :not_found} -> {:ok, show_active_theme(socket, :expired)}
    end
  end

  @impl true
  def handle_info({:theme_editing_session_updated, revision}, socket) do
    case ThemeEditing.fetch(socket.assigns.session_id) do
      {:ok, session} -> {:noreply, show_theme(socket, session.theme, revision, :editing)}
      {:error, :not_found} -> {:noreply, show_active_theme(socket, :expired)}
    end
  end

  def handle_info({:theme_editing_session_closed, reason}, socket)
      when reason in [:published, :discarded, :expired] do
    {:noreply, show_active_theme(socket, reason)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="theme-preview" data-state={@status}>
      <iframe
        id="theme-preview-site"
        data-part="site"
        title={"Preview of #{@site.name}"}
        srcdoc={@document}
        sandbox="allow-forms allow-popups allow-popups-to-escape-sandbox allow-scripts allow-top-navigation-by-user-activation"
      ></iframe>
      <aside
        id="theme-preview-status"
        data-part="status"
        data-state={@status}
        data-revision={@revision}
        role="status"
        aria-live="polite"
      >
        <span data-part="signal" aria-hidden="true"></span>
        <span data-part="copy">
          <strong>{@status_title}</strong>
          <span data-part="detail">{@status_detail}</span>
        </span>
      </aside>
    </div>
    """
  end

  defp show_active_theme(socket, status) do
    site = Sites.get_site!(socket.assigns.site.id)

    socket
    |> assign(:site, site)
    |> show_theme(Sites.get_theme!(site), socket.assigns[:revision] || 0, status)
  end

  defp show_theme(socket, theme, revision, status) do
    {status_title, status_detail} = status_copy(status, revision)

    socket
    |> assign(
      :document,
      render_document(
        socket.assigns.site,
        theme,
        socket.assigns.page,
        socket.assigns.session_id
      )
    )
    |> assign(:revision, revision)
    |> assign(:status, status)
    |> assign(:status_detail, status_detail)
    |> assign(:status_title, status_title)
  end

  defp render_document(site, theme, page, session_id) do
    html =
      case render_page(site, theme, page) do
        {:ok, html} -> html
        {:error, reason} -> render_error(reason)
      end

    html
    |> rewrite_public_paths(ThemeEditing.preview_path(session_id))
    |> inject_frame_support()
  end

  defp render_page(site, theme, %{"kind" => "home"}) do
    Renderer.render_index(
      site,
      theme,
      Publishing.list_published_posts(site),
      Publishing.list_published_pages(site)
    )
  end

  defp render_page(site, theme, %{"kind" => "article", "slug" => slug}) do
    post = Publishing.get_published_post_by_slug!(site, :post, slug)
    Renderer.render_article(site, theme, post, Publishing.list_published_pages(site))
  end

  defp render_page(site, theme, %{"kind" => "page", "slug" => slug}) do
    page = Publishing.get_published_post_by_slug!(site, :page, slug)
    Renderer.render_page(site, theme, page, Publishing.list_published_pages(site))
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

  defp inject_frame_support(html) do
    support = """
    <base target="_top">
    <meta name="robots" content="noindex, nofollow">
    <meta name="referrer" content="no-referrer">
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
      <body><main><h1>Theme preview could not be rendered</h1><pre>#{message}</pre><p>Keep editing. This page will refresh after the next theme change.</p></main></body>
    </html>
    """
  end

  defp status_copy(:editing, revision),
    do: {"Theme editing", "Live preview · Revision #{revision}"}

  defp status_copy(:published, _revision),
    do: {"Theme published", "The previewed theme is now persisted."}

  defp status_copy(:discarded, _revision),
    do: {"Changes discarded", "Showing the published theme again."}

  defp status_copy(:expired, _revision),
    do: {"Editing session ended", "Showing the published theme again."}
end
