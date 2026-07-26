defmodule GesttaltWeb.ThemePreviewLive do
  use GesttaltWeb, :live_view

  alias Gesttalt.Photography
  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing
  alias Gesttalt.Themes.Renderer

  @screenshot_upload :theme_preview_screenshot

  @impl true
  def mount(
        _params,
        %{"page" => page, "session_id" => session_id, "site_id" => site_id},
        socket
      ) do
    site = Sites.get_site!(site_id)
    page = enrich_page(site, page)

    socket =
      socket
      |> allow_upload(@screenshot_upload,
        accept: ~w(.png),
        auto_upload: true,
        max_entries: 1,
        max_file_size: 8_000_000,
        progress: &handle_screenshot_progress/3
      )
      |> assign(:client_id, nil)
      |> assign(:page, page)
      |> assign(:page_title, "Theme preview · #{site.name}")
      |> assign(:screenshot_enabled, false)
      |> assign(:session_id, session_id)
      |> assign(:site, site)

    socket =
      case ThemeEditing.fetch(session_id) do
        {:ok, session} -> show_theme(socket, session.theme, session.revision, :editing)
        {:error, :not_found} -> show_active_theme(socket, :expired)
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Gesttalt.PubSub, ThemeEditing.topic(session_id))
      {:ok, connect_preview(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:theme_editing_session_updated, _revision}, socket) do
    case ThemeEditing.fetch(socket.assigns.session_id) do
      {:ok, session} ->
        {:noreply, show_theme(socket, session.theme, session.revision, :editing)}

      {:error, :not_found} ->
        {:noreply, show_active_theme(socket, :expired)}
    end
  end

  def handle_info({:theme_preview_navigate, page}, socket) do
    {:noreply, navigate_to_page(socket, page)}
  end

  def handle_info({:theme_preview_capture, request_id}, socket) do
    {:noreply,
     push_event(socket, "theme-preview:capture", %{
       request_id: request_id
     })}
  end

  def handle_info({:theme_editing_session_closed, reason}, socket)
      when reason in [:published, :discarded, :expired] do
    socket =
      socket
      |> assign(:screenshot_enabled, false)
      |> push_event("theme-preview:stop-capture", %{})
      |> show_active_theme(reason)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-theme-preview-screenshot", _params, socket),
    do: {:noreply, socket}

  def handle_event("theme-preview-screenshot-access", %{"enabled" => enabled}, socket)
      when is_boolean(enabled) do
    socket = assign(socket, :screenshot_enabled, enabled)
    update_presence(socket, %{screenshots_enabled: enabled})
    {:noreply, socket}
  end

  def handle_event("theme-preview-presence", %{"viewport" => viewport}, socket) do
    viewport = normalize_viewport(viewport)
    update_presence(socket, %{viewport: viewport})
    {:noreply, socket}
  end

  def handle_event("navigate-theme-preview", %{"path" => path}, socket) do
    result =
      ThemeEditing.navigate_preview(
        socket.assigns.session_id,
        socket.assigns.site,
        socket.assigns.client_id,
        path
      )

    case result do
      {:ok, preview} -> {:reply, %{navigating: true, preview: preview}, socket}
      {:error, reason} -> {:reply, %{error: to_string(reason)}, socket}
    end
  end

  def handle_event(
        "theme-preview-screenshot-failed",
        %{"reason" => reason, "request_id" => request_id},
        socket
      ) do
    _result =
      ThemeEditing.fail_preview_screenshot(
        socket.assigns.session_id,
        socket.assigns.client_id,
        request_id,
        capture_error(reason)
      )

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="theme-preview"
      data-path={ThemeEditing.public_page_path(@page)}
      data-screenshots={to_string(@screenshot_enabled)}
      data-state={@status}
      phx-hook="ThemePreview"
    >
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
        <button
          :if={@status == :editing}
          id="theme-preview-enable-screenshots"
          data-action="enable-screenshots"
          data-part="screenshot-action"
          disabled={@screenshot_enabled}
          type="button"
        >
          <%= if @screenshot_enabled do %>
            Screenshots enabled
          <% else %>
            Allow screenshots
          <% end %>
        </button>
      </aside>
      <form
        id="theme-preview-screenshot-upload"
        data-part="screenshot-upload"
        phx-change="validate-theme-preview-screenshot"
      >
        <.live_file_input upload={@uploads.theme_preview_screenshot} />
      </form>
    </div>
    """
  end

  defp connect_preview(socket) do
    connect_params = get_connect_params(socket) || %{}
    client_id = valid_client_id(connect_params["theme_preview_client_id"])
    viewport = normalize_viewport(connect_params["theme_preview_viewport"] || %{})
    socket = assign(socket, :client_id, client_id)

    {:ok, _preview} =
      ThemeEditing.connect_preview(
        socket.assigns.session_id,
        socket.assigns.site,
        client_id,
        self(),
        preview_attrs(socket, viewport)
      )

    socket
  end

  defp navigate_to_page(socket, page) do
    socket = assign(socket, :page, page)

    socket =
      case {socket.assigns.status, ThemeEditing.fetch(socket.assigns.session_id)} do
        {:editing, {:ok, session}} ->
          show_theme(socket, session.theme, session.revision, :editing)

        {_status, _result} ->
          show_active_theme(socket, socket.assigns.status)
      end

    update_presence(socket, preview_attrs(socket, nil))

    push_event(socket, "theme-preview:navigated", %{
      path: ThemeEditing.preview_page_path(socket.assigns.session_id, page)
    })
  end

  defp update_presence(%{assigns: %{client_id: nil}}, _attrs), do: :ok

  defp update_presence(socket, attrs) do
    ThemeEditing.update_preview(
      socket.assigns.session_id,
      socket.assigns.site,
      socket.assigns.client_id,
      attrs
    )
  end

  defp preview_attrs(socket, viewport) do
    attrs = %{
      page: socket.assigns.page,
      path: ThemeEditing.public_page_path(socket.assigns.page),
      preview_path:
        ThemeEditing.preview_page_path(socket.assigns.session_id, socket.assigns.page),
      screenshots_enabled: socket.assigns.screenshot_enabled
    }

    if is_nil(viewport), do: attrs, else: Map.put(attrs, :viewport, viewport)
  end

  defp handle_screenshot_progress(@screenshot_upload, entry, socket) do
    if entry.done?, do: complete_screenshot_upload(socket, entry)

    {:noreply, socket}
  end

  defp complete_screenshot_upload(socket, entry) do
    with {:ok, request_id, width, height} <- screenshot_metadata(entry.client_name),
         data <- read_screenshot_upload(socket, entry) do
      _result =
        ThemeEditing.complete_preview_screenshot(
          socket.assigns.session_id,
          socket.assigns.client_id,
          request_id,
          %{data: data, height: height, mime_type: "image/png", width: width}
        )
    end
  end

  defp read_screenshot_upload(socket, entry) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok, File.read!(path)}
    end)
  end

  defp screenshot_metadata(filename) do
    case Regex.run(~r/\A([A-Za-z0-9_-]+)--([0-9]+)x([0-9]+)\.png\z/, filename) do
      [_filename, request_id, width, height] ->
        {:ok, request_id, String.to_integer(width), String.to_integer(height)}

      _match ->
        {:error, :invalid_screenshot_filename}
    end
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
    |> inject_frame_support(ThemeEditing.preview_path(session_id))
  end

  defp render_page(site, theme, %{"kind" => "home"}) do
    {posts, pagination} = Publishing.paginate_published_posts(site)

    Renderer.render_index(
      site,
      theme,
      posts,
      Publishing.list_published_pages(site),
      pagination
    )
  end

  defp render_page(site, theme, %{"kind" => "article", "slug" => slug}) do
    post = Publishing.get_published_post_by_slug!(site, :post, slug)
    Renderer.render_article(site, theme, post, Publishing.list_published_pages(site))
  end

  defp render_page(site, theme, %{"kind" => "photography"}) do
    Renderer.render_photography(
      site,
      theme,
      Photography.list_published_photos(site),
      Publishing.list_published_pages(site)
    )
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

  defp inject_frame_support(html, prefix) do
    support = """
    <base target="_top">
    <meta name="robots" content="noindex, nofollow">
    <meta name="referrer" content="no-referrer">
    <script data-theme-preview-navigation>
      (() => {
        const prefix = #{JSON.encode!(prefix)};

        document.addEventListener("click", event => {
          if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

          const link = event.target.closest?.("a[href]");
          if (!link) return;

          const path = new URL(link.getAttribute("href"), "https://preview.invalid").pathname;
          if (path !== prefix && !path.startsWith(`${prefix}/`)) return;

          event.preventDefault();
          parent.postMessage({type: "gesttalt:theme-preview:navigate", path}, "*");
        }, true);
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
      <body><main><h1>Theme preview could not be rendered</h1><pre>#{message}</pre><p>Keep editing. This page will refresh after the next theme change.</p></main></body>
    </html>
    """
  end

  defp enrich_page(site, page) do
    case ThemeEditing.page_for_path(site, "", ThemeEditing.public_page_path(page)) do
      {:ok, enriched_page} -> enriched_page
      {:error, :preview_page_not_found} -> page
    end
  end

  defp valid_client_id(client_id) when is_binary(client_id) and byte_size(client_id) in 16..128,
    do: client_id

  defp valid_client_id(_client_id), do: Ecto.UUID.generate()

  defp normalize_viewport(viewport) do
    %{
      device_pixel_ratio: positive_number(viewport["device_pixel_ratio"]),
      height: positive_integer(viewport["height"]),
      width: positive_integer(viewport["width"])
    }
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp positive_number(value) when is_number(value) and value > 0, do: value
  defp positive_number(_value), do: nil

  defp capture_error("capture_stream_ended"), do: :capture_stream_ended
  defp capture_error("screenshot_permission_required"), do: :screenshot_permission_required
  defp capture_error(_reason), do: :capture_failed

  defp status_copy(:editing, revision),
    do: {"Theme editing", "Live preview · Revision #{revision}"}

  defp status_copy(:published, _revision),
    do: {"Theme published", "The previewed theme is now persisted."}

  defp status_copy(:discarded, _revision),
    do: {"Changes discarded", "Showing the published theme again."}

  defp status_copy(:expired, _revision),
    do: {"Editing session ended", "Showing the published theme again."}
end
