defmodule GesttaltWeb.FeedControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Gesttalt.PublishingFixtures

  alias Gesttalt.AccountsFixtures

  setup do
    site = AccountsFixtures.site_fixture()
    host = site.domains |> List.first() |> Map.fetch!(:hostname)

    newer_post =
      post_fixture(%{
        site: site,
        title: "Newest & brightest",
        slug: "newest",
        excerpt: "The latest <dispatch>",
        body: "A **complete** article.",
        status: :published,
        published_at: ~U[2026-07-20 12:00:00Z]
      })

    older_post =
      post_fixture(%{
        site: site,
        title: "An older post",
        slug: "older",
        status: :published,
        published_at: ~U[2026-07-19 12:00:00Z]
      })

    post_fixture(%{site: site, title: "A draft", slug: "draft"})
    post_fixture(%{site: site, title: "A page", slug: "page", kind: :page, status: :published})

    %{host: host, newer_post: newer_post, older_post: older_post, site: site}
  end

  test "serves the website-compatible Really Simple Syndication feed", %{
    conn: conn,
    host: host,
    newer_post: newer_post,
    older_post: older_post,
    site: site
  } do
    conn =
      conn
      |> Map.put(:host, host)
      |> put_req_header("accept", "application/rss+xml")
      |> get(~p"/blog/feed.xml")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/rss+xml; charset=utf-8"]
    assert body =~ ~s(<rss version="2.0")
    assert body =~ "<title>#{site.name}</title>"
    assert body =~ "<atom:link href=\"http://#{host}/blog/feed.xml\""
    assert body =~ "<title>Newest &amp; brightest</title>"
    assert body =~ "<description>The latest &lt;dispatch&gt;</description>"
    assert body =~ "<pubDate>Mon, 20 Jul 2026 12:00:00 +0000</pubDate>"
    assert body =~ "<content:encoded><![CDATA[<p>A <strong>complete</strong> article.</p>"
    assert body =~ "http://#{host}/blog/#{newer_post.slug}/"
    assert body =~ "http://#{host}/blog/#{older_post.slug}/"
    assert before?(body, "/blog/#{newer_post.slug}/", "/blog/#{older_post.slug}/")
    refute body =~ "A draft"
    refute body =~ "A page"
  end

  test "also serves the Really Simple Syndication feed from its explicit path", %{
    conn: conn,
    host: host
  } do
    conn =
      conn
      |> Map.put(:host, host)
      |> put_req_header("accept", "application/rss+xml")
      |> get(~p"/blog/rss.xml")

    assert response(conn, 200) =~ ~s(<rss version="2.0")
    assert get_resp_header(conn, "content-type") == ["application/rss+xml; charset=utf-8"]
  end

  test "serves an Atom feed with full article content", %{
    conn: conn,
    host: host,
    newer_post: newer_post,
    older_post: older_post
  } do
    conn =
      conn
      |> Map.put(:host, host)
      |> put_req_header("accept", "application/atom+xml")
      |> get(~p"/blog/atom.xml")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/atom+xml; charset=utf-8"]
    assert body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
    assert body =~ ~s(<link href="http://#{host}/blog/atom.xml" rel="self")
    assert body =~ "<title>Newest &amp; brightest</title>"
    assert body =~ "<summary>The latest &lt;dispatch&gt;</summary>"
    assert body =~ "&lt;p&gt;A &lt;strong&gt;complete&lt;/strong&gt; article.&lt;/p&gt;"
    assert body =~ "http://#{host}/blog/#{newer_post.slug}/"
    assert body =~ "http://#{host}/blog/#{older_post.slug}/"
    assert before?(body, "/blog/#{newer_post.slug}/", "/blog/#{older_post.slug}/")
    refute body =~ "A draft"
    refute body =~ "A page"
  end

  test "advertises both feed formats from the default theme", %{conn: conn, host: host} do
    body = conn |> Map.put(:host, host) |> get(~p"/") |> html_response(200)

    assert body =~ ~s(type="application/rss+xml")
    assert body =~ ~s(href="/blog/feed.xml")
    assert body =~ ~s(type="application/atom+xml")
    assert body =~ ~s(href="/blog/atom.xml")
  end

  defp before?(body, first, second) do
    {first_position, _length} = :binary.match(body, first)
    {second_position, _length} = :binary.match(body, second)
    first_position < second_position
  end
end
