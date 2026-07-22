defmodule GesttaltWeb.ThemePreviewControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.PublishingFixtures
  alias Gesttalt.Sites
  alias Gesttalt.ThemeEditing

  setup do
    site = AccountsFixtures.site_fixture()
    {:ok, site} = Sites.update_billing(site, %{subscription_status: :trialing})

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

    on_exit(fn -> ThemeEditing.discard(session.id, site) end)

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
end
