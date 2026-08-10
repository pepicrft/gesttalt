defmodule GesttaltWeb.AdminControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Gesttalt.PublishingFixtures

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "shows the publication date for published content", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    published_at = ~U[2017-12-25 12:00:00Z]

    post_fixture(%{
      site: site,
      title: "A post from the archive",
      status: :published,
      published_at: published_at
    })

    response = conn |> get(~p"/admin/") |> html_response(200)

    assert response =~ "25 Dec 2017, 12:00"
    assert response =~ ~s(datetime="2017-12-25T12:00:00Z")
  end

  test "uses the active development port for public content links", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    domain = Enum.find(site.domains, &(&1.status == :active))

    post =
      post_fixture(%{
        site: site,
        status: :published,
        title: "A visible post",
        slug: "a-visible-post"
      })

    response =
      conn
      |> Map.put(:host, "sc-flux-boson-0165.localhost")
      |> Map.put(:port, 4817)
      |> get(~p"/admin/")
      |> html_response(200)

    assert response =~ "http://#{domain.hostname}:4817/blog/#{post.slug}/"
  end

  test "provides a titleless short note editor", %{conn: conn} do
    response = conn |> get(~p"/admin/notes/new") |> html_response(200)

    assert response =~ "New note"
    assert response =~ "Write up to 500 characters"
    assert response =~ ~s(name="post[body]")
    assert response =~ ~s(maxlength="500")
    assert response =~ ~s(name="post[kind]" value="note")
    refute response =~ ~s(name="post[title]")
  end

  test "shows cookie-free page-view counts", %{conn: conn, user: user} do
    {:ok, site} = Sites.ensure_site_for_user(user)
    {:ok, _page_view} = Gesttalt.Analytics.record_page_view(site, %{path: "/", country: "ES"})

    response = conn |> get(~p"/admin/analytics") |> html_response(200)

    assert response =~ "Cookie-free page-view counts. No visitors are identified or tracked."
    assert response =~ ~s(value="30" selected)
    assert response =~ ~s(id="analytics-world-map")
    assert response =~ ~s(data-country="ES")
    assert response =~ ~s(data-longitude="-4")
    assert response =~ ~s(src="/assets/js/analytics_map.js")
    assert response =~ ~s(<code>/</code><span>1</span>)
  end
end
