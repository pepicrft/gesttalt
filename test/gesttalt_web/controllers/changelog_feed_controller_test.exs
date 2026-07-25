defmodule GesttaltWeb.ChangelogFeedControllerTest do
  use GesttaltWeb.ConnCase, async: true

  test "serves the changelog Really Simple Syndication feed", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "gesttalt.test")
      |> put_req_header("accept", "application/rss+xml")
      |> get(~p"/changelog/feed.xml")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/rss+xml; charset=utf-8"]
    assert body =~ ~s(<rss version="2.0")
    assert body =~ "<title>Gesttalt changelog</title>"
    assert body =~ ~s(<atom:link href="http://gesttalt.test/changelog/feed.xml")
    assert body =~ "<title>Follow what changes in Gesttalt</title>"
    assert body =~ "<pubDate>Sat, 25 Jul 2026 12:00:00 +0000</pubDate>"
    assert body =~ "http://gesttalt.test/changelog#changelog-entry-follow-gesttalt-updates"
    assert body =~ "<content:encoded><![CDATA[<p>Gesttalt now has a public home"
  end

  test "also serves the changelog Really Simple Syndication feed from its explicit path", %{
    conn: conn
  } do
    conn =
      conn
      |> Map.put(:host, "gesttalt.test")
      |> put_req_header("accept", "application/rss+xml")
      |> get(~p"/changelog/rss.xml")

    assert response(conn, 200) =~ ~s(<rss version="2.0")
  end

  test "serves the changelog Atom feed", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "gesttalt.test")
      |> put_req_header("accept", "application/atom+xml")
      |> get(~p"/changelog/atom.xml")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/atom+xml; charset=utf-8"]
    assert body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
    assert body =~ ~s(<link href="http://gesttalt.test/changelog/atom.xml" rel="self")
    assert body =~ "<title>Follow what changes in Gesttalt</title>"
    assert body =~ "<published>2026-07-25T12:00:00Z</published>"
    assert body =~ "&lt;p&gt;Gesttalt now has a public home"
  end
end
