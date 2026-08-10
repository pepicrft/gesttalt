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
    assert get_resp_header(conn, "vary") == ["accept, cookie"]
  end

  test "does not show publication controls to anonymous visitors", %{conn: conn, host: host} do
    conn = conn |> Map.put(:host, host) |> get(~p"/")
    body = html_response(conn, 200)

    refute body =~ ~s(id="gesttalt-owner-controls")
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(conn, "vary") == ["accept, cookie"]
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

  test "serves every public publication route as negotiated Markdown", %{
    conn: conn,
    host: host,
    site: site
  } do
    {:ok, post} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{
          site: site,
          title: "Agent-readable post",
          body: "## A heading\n\nPublished in **Markdown**.",
          tags: ["agents"]
        })
      )

    {:ok, page} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{
          site: site,
          kind: :page,
          slug: "about",
          title: "About this publication",
          body: "A public page."
        })
      )

    for {path, expected} <- [
          {"/", "# #{site.name}"},
          {"/blog", "[Agent-readable post](/blog/#{post.slug}.md)"},
          {"/blog/#{post.slug}", "Published in **Markdown**."},
          {"/#{page.slug}", "# About this publication"},
          {"/photography", "# Photography from #{site.name}"}
        ] do
      markdown_conn =
        conn
        |> recycle()
        |> Map.put(:host, host)
        |> put_req_header("accept", "text/markdown")
        |> get(path)

      markdown = response(markdown_conn, 200)

      assert markdown =~ expected
      assert get_resp_header(markdown_conn, "content-type") == ["text/markdown; charset=utf-8"]
    end
  end

  test "provides Markdown routes and a publication index for agents", %{
    conn: conn,
    host: host,
    site: site
  } do
    {:ok, post} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{
          site: site,
          title: "A linked post",
          slug: "linked-post"
        })
      )

    {:ok, page} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{
          site: site,
          kind: :page,
          title: "A linked page",
          slug: "linked-page"
        })
      )

    article = conn |> Map.put(:host, host) |> get("/blog/#{post.slug}.md")
    assert response(article, 200) =~ "# A linked post"
    assert get_resp_header(article, "content-type") == ["text/markdown; charset=utf-8"]

    index = conn |> recycle() |> Map.put(:host, host) |> get("/llms.txt")
    assert response(index, 200) =~ "[A linked page](/#{page.slug}.md)"
    assert response(index, 200) =~ "[A linked post](/blog/#{post.slug}.md)"
    assert get_resp_header(index, "content-type") == ["text/markdown; charset=utf-8"]
  end

  test "negotiates HTML or Markdown for the same article URL from the Accept header", %{
    conn: conn,
    host: host,
    site: site
  } do
    {:ok, post} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{
          site: site,
          title: "Negotiated content",
          body: "## Markdown heading"
        })
      )

    html =
      conn
      |> Map.put(:host, host)
      |> put_req_header("accept", "text/html")
      |> get("/blog/#{post.slug}")

    assert html_response(html, 200) =~ "<h2>Markdown heading</h2>"
    assert get_resp_header(html, "content-type") == ["text/html; charset=utf-8"]

    markdown =
      conn
      |> recycle()
      |> Map.put(:host, host)
      |> put_req_header("accept", "text/markdown;q=1.0, text/html;q=0.8")
      |> get("/blog/#{post.slug}")

    assert response(markdown, 200) =~ "## Markdown heading"
    assert get_resp_header(markdown, "content-type") == ["text/markdown; charset=utf-8"]
    assert get_resp_header(markdown, "vary") == ["accept"]
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

  test "adds canonical social metadata to every public publication route", %{
    conn: conn,
    host: host,
    site: site
  } do
    {:ok, post} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{site: site, title: "An article"})
      )

    {:ok, page} =
      Gesttalt.Publishing.publish_post(
        PublishingFixtures.post_fixture(%{site: site, kind: :page, slug: "about", title: "About"})
      )

    for {path, type, title} <- [
          {"/", "website", site.name},
          {"/blog", "website", "Writing · #{site.name}"},
          {"/blog/#{post.slug}", "article", post.title},
          {"/#{page.slug}", "website", page.title},
          {"/photography", "website", "Photography · #{site.name}"}
        ] do
      body = conn |> recycle() |> Map.put(:host, host) |> get(path) |> html_response(200)

      assert body =~ ~s(<meta property="og:type" content="#{type}">)
      assert body =~ ~s(<meta property="og:title" content="#{title}">)

      assert body =~
               ~r/<meta property="og:image" content="https?:\/\/#{Regex.escape(host)}\/og-image\?/

      assert body =~ ~s(<meta name="twitter:card" content="summary_large_image">)

      assert body =~
               ~r/<meta name="twitter:image" content="https?:\/\/#{Regex.escape(host)}\/og-image\?/

      assert length(Regex.scan(~r/<meta property="og:image"/, body)) == 1
    end
  end
end
