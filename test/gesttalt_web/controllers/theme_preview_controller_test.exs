defmodule GesttaltWeb.ThemePreviewControllerTest do
  use GesttaltWeb.ConnCase, async: true

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
    assert body =~ "new EventSource"
    assert body =~ "/theme-previews/#{session.id}/events"
    assert body =~ ~s|changes.addEventListener("ready", reloadForRevision)|
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

  test "keeps automatic reload available while a draft cannot render", %{
    conn: conn,
    session: session,
    site: site
  } do
    assert {:ok, _session} =
             ThemeEditing.update(session.id, site, %{index_template: "{% if broken"})

    body = conn |> get("/theme-previews/#{session.id}") |> html_response(200)

    assert body =~ "Theme preview could not be rendered"
    assert body =~ "Keep editing"
    assert body =~ "new EventSource"
  end

  test "returns not found after a session closes", %{conn: conn, session: session, site: site} do
    assert :ok = ThemeEditing.discard(session.id, site)

    conn = get(conn, "/theme-previews/#{session.id}")
    assert response(conn, 404) =~ "not found or expired"
  end
end
