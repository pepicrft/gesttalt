defmodule GesttaltWeb.ThemePreviewControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.PublishingFixtures
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing

  setup do
    site = AccountsFixtures.site_fixture()
    post =
      PublishingFixtures.post_fixture(%{
        site: site,
        title: "Previewed post",
        status: :published
      })

    page =
      PublishingFixtures.post_fixture(%{
        site: site,
        kind: :page,
        title: "Previewed page",
        status: :published
      })

    {:ok, session} = ThemeEditing.create(site)

    on_exit(fn -> terminate_session(session.id) end)

    %{page: page, post: post, session: session, site: site}
  end

  test "renders real publication content through the isolated theme", %{
    conn: conn,
    page: page,
    post: post,
    session: session
  } do
    conn = get(conn, "/theme-previews/#{session.id}")
    body = html_response(conn, 200)

    assert body =~ "Previewed post"
    assert body =~ "/theme-previews/#{session.id}/blog/#{post.slug}/"
    assert body =~ "/theme-previews/#{session.id}/#{page.slug}/"
    assert body =~ "theme-preview-site"
    assert body =~ "theme-preview-status"
    assert body =~ ~s(id="theme-preview")
    assert body =~ "Theme editing"
    assert body =~ "Live preview · Revision 0"
    assert body =~ "data-phx-session"
    refute body =~ "EventSource"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "renders article and page routes inside the preview", %{
    conn: conn,
    page: page,
    post: post,
    session: session
  } do
    article = conn |> get("/theme-previews/#{session.id}/blog/#{post.slug}") |> html_response(200)
    assert article =~ "Previewed post"

    page_body =
      conn |> recycle() |> get("/theme-previews/#{session.id}/#{page.slug}") |> html_response(200)

    assert page_body =~ "Previewed page"
  end

  test "refreshes the connected preview for each accepted edit", %{
    conn: conn,
    session: session,
    site: site
  } do
    {:ok, view, _html} = live(conn, "/theme-previews/#{session.id}")

    assert {:ok, _session} =
             ThemeEditing.update(session.id, site, %{
               stylesheet: "body { background: papayawhip; }"
             })

    html = render(view)
    assert html =~ ~s(id="theme-preview")
    assert html =~ "body { background: papayawhip; }"
    assert html =~ "Live preview · Revision 1"
    assert html =~ ~s(data-state="editing")
  end

  test "reports its current page and accepts remote navigation", %{
    conn: conn,
    post: post,
    session: session,
    site: site
  } do
    {:ok, view, _html} = live(conn, "/theme-previews/#{session.id}")

    assert {:ok, [preview]} = ThemeEditing.list_previews(session.id, site)
    assert preview.path == "/"
    assert preview.page["kind"] == "home"

    assert {:ok, navigated} =
             ThemeEditing.navigate_preview(
               session.id,
               site,
               preview.client_id,
               "/blog/#{post.slug}"
             )

    assert navigated.path == "/blog/#{post.slug}"

    assert_eventually(fn ->
      html = render(view)
      html =~ "Previewed post" and html =~ ~s(data-path="/blog/#{post.slug}")
    end)

    assert {:ok, [current_preview]} = ThemeEditing.list_previews(session.id, site)
    assert current_preview.path == "/blog/#{post.slug}"
    assert current_preview.page["title"] == "Previewed post"
  end

  test "uploads a permitted browser screenshot for a waiting request", %{
    conn: conn,
    session: session,
    site: site
  } do
    {:ok, view, _html} = live(conn, "/theme-previews/#{session.id}")
    assert {:ok, [preview]} = ThemeEditing.list_previews(session.id, site)

    render_hook(view, "theme-preview-screenshot-access", %{"enabled" => true})

    capture =
      Task.async(fn ->
        ThemeEditing.capture_preview(session.id, site, preview.client_id)
      end)

    assert_push_event view, "theme-preview:capture", %{request_id: request_id}

    filename = "#{request_id}--2x1.png"

    upload =
      file_input(view, "#theme-preview-screenshot-upload", :theme_preview_screenshot, [
        %{
          content: "client png",
          last_modified: 1_700_000_000_000,
          name: filename,
          type: "image/png"
        }
      ])

    render_upload(upload, filename)

    assert {:ok, screenshot} = Task.await(capture)
    assert screenshot.data == "client png"
    assert screenshot.width == 2
    assert screenshot.height == 1
    assert screenshot.client_id == preview.client_id
  end

  test "keeps live refresh available while a draft cannot render", %{
    conn: conn,
    session: session,
    site: site
  } do
    assert {:ok, _session} =
             ThemeEditing.update(session.id, site, %{index_template: "{% if broken"})

    body = conn |> get("/theme-previews/#{session.id}") |> html_response(200)

    assert body =~ "Theme preview could not be rendered"
    assert body =~ "Keep editing"
    assert body =~ "data-phx-session"
  end

  test "shows the persisted theme after publishing", %{conn: conn, session: session, site: site} do
    {:ok, view, _html} = live(conn, "/theme-previews/#{session.id}")

    assert {:ok, _session} =
             ThemeEditing.update(session.id, site, %{
               stylesheet: "body { background: papayawhip; }"
             })

    assert {:ok, _theme} = ThemeEditing.publish(session.id, site)

    html = render(view)
    assert html =~ "body { background: papayawhip; }"
    assert html =~ "Theme published"
    assert html =~ "The previewed theme is now persisted."
    assert html =~ ~s(data-state="published")
  end

  test "restores the published theme after discarding", %{
    conn: conn,
    session: session,
    site: site
  } do
    original_stylesheet = Sites.get_theme!(site).stylesheet
    {:ok, view, _html} = live(conn, "/theme-previews/#{session.id}")

    assert {:ok, _session} =
             ThemeEditing.update(session.id, site, %{
               stylesheet: "body { background: papayawhip; }"
             })

    assert render(view) =~ "body { background: papayawhip; }"
    assert :ok = ThemeEditing.discard(session.id, site)

    html = render(view)

    escaped_stylesheet =
      original_stylesheet |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    assert html =~ escaped_stylesheet
    refute html =~ "body { background: papayawhip; }"
    assert html =~ "Changes discarded"
    assert html =~ "Showing the published theme again."
    assert html =~ ~s(data-state="discarded")
  end

  test "returns not found after a session closes", %{conn: conn, session: session, site: site} do
    assert :ok = ThemeEditing.discard(session.id, site)

    conn = get(conn, "/theme-previews/#{session.id}")
    assert response(conn, 404) =~ "not found or expired"
  end

  defp assert_eventually(assertion, attempts \\ 20)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")

  defp terminate_session(session_id) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{process, _value}] ->
        DynamicSupervisor.terminate_child(Gesttalt.ThemeEditing.SessionSupervisor, process)

      [] ->
        :ok
    end
  end
end
