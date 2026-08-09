defmodule GesttaltWeb.SiteControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.PublishingFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    site = AccountsFixtures.site_fixture(user)
    host = site.domains |> List.first() |> Map.fetch!(:hostname)

    %{host: host, site: site, user: user}
  end

  test "shows publication controls to the signed-in owner", %{
    conn: conn,
    host: host,
    user: user
  } do
    conn = conn |> log_in_user(user) |> Map.put(:host, host) |> get(~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(id="gesttalt-owner-controls")
    assert body =~ ~s(href="/admin/")
    assert body =~ "</aside>\n</body>"
    refute body =~ "<<style"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "vary") == ["cookie"]
  end

  test "does not show publication controls to anonymous visitors", %{conn: conn, host: host} do
    conn = conn |> Map.put(:host, host) |> get(~p"/")
    body = html_response(conn, 200)

    refute body =~ ~s(id="gesttalt-owner-controls")
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(conn, "vary") == ["cookie"]
  end

  test "does not show publication controls to another signed-in user", %{
    conn: conn,
    host: host
  } do
    visitor = AccountsFixtures.user_fixture()

    body =
      conn
      |> log_in_user(visitor)
      |> Map.put(:host, host)
      |> get(~p"/")
      |> html_response(200)

    refute body =~ ~s(id="gesttalt-owner-controls")
  end

  test "shows a Markdown description and the three newest posts on the home page", %{
    conn: conn,
    host: host,
    site: site
  } do
    {:ok, site} =
      Gesttalt.Sites.update_site(site, %{description: "## Hello\n\nI write about **software**."})

    Enum.each(1..4, fn index ->
      PublishingFixtures.post_fixture(%{
        site: site,
        title: "Article #{index}",
        status: :published,
        published_at: DateTime.add(~U[2026-01-01 00:00:00Z], index, :day)
      })
    end)

    home = conn |> Map.put(:host, host) |> get(~p"/") |> html_response(200)

    assert home =~ ~s(id="site-home")
    assert home =~ "<h2>Hello</h2>"
    assert home =~ "<strong>software</strong>"
    assert home =~ ">Article 4</a>"
    assert home =~ ">Article 2</a>"
    refute home =~ ">Article 1</a>"
    assert home =~ ~s(href="/blog">View all writing</a>)
  end

  test "paginates published posts in the writing archive", %{
    conn: conn,
    host: host,
    site: site
  } do
    Enum.each(1..21, fn index ->
      PublishingFixtures.post_fixture(%{
        site: site,
        title: "Article #{index}",
        status: :published,
        published_at: DateTime.add(~U[2026-01-01 00:00:00Z], index, :day)
      })
    end)

    first_page = conn |> Map.put(:host, host) |> get(~p"/blog") |> html_response(200)

    assert first_page =~ ~s(id="site-blog")
    assert first_page =~ ">Article 21</a>"
    assert first_page =~ ">Article 2</a>"
    refute first_page =~ ">Article 1</a>"
    assert first_page =~ ~s(id="posts-pagination")
    assert first_page =~ ~s(href="/blog?page=2")
    assert first_page =~ "Page 1 of 2"

    second_page =
      conn
      |> recycle()
      |> Map.put(:host, host)
      |> get(~p"/blog?page=2")
      |> html_response(200)

    assert second_page =~ ">Article 1</a>"
    refute second_page =~ ">Article 2</a>"
    assert second_page =~ ~s(href="/blog")
    assert second_page =~ "Page 2 of 2"
  end

  test "redirects an archive page beyond the end to the last page", %{
    conn: conn,
    host: host,
    site: site
  } do
    PublishingFixtures.post_fixture(%{site: site, status: :published})

    conn = conn |> Map.put(:host, host) |> get(~p"/blog?page=3")

    assert redirected_to(conn) == "/blog"
  end
end
