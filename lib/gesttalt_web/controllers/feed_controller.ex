defmodule GesttaltWeb.FeedController do
  use GesttaltWeb, :controller

  alias Gesttalt.Markdown
  alias Gesttalt.Publishing

  def atom(%{assigns: %{current_site: site}} = conn, _params) do
    posts = Publishing.list_published_posts(site)
    updated_at = latest_updated_at(posts, site)
    entries = Enum.map_join(posts, "\n", &atom_entry(&1, conn))

    feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <id>#{origin(conn)}/</id>
      <title>#{escape(site.name)}</title>
      <subtitle>#{escape(site.tagline || "")}</subtitle>
      <updated>#{DateTime.to_iso8601(updated_at)}</updated>
      <link href="#{origin(conn)}/blog/atom.xml" rel="self" type="application/atom+xml" />
      <link href="#{origin(conn)}/" />
      #{entries}
    </feed>
    """

    conn |> put_resp_content_type("application/atom+xml") |> send_resp(200, feed)
  end

  def rss(%{assigns: %{current_site: site}} = conn, _params) do
    items =
      site
      |> Publishing.list_published_posts()
      |> Enum.map_join("\n", &rss_item(&1, conn))

    feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>#{escape(site.name)}</title>
        <link>#{origin(conn)}/</link>
        <description>#{escape(site.tagline || "")}</description>
        <atom:link href="#{origin(conn)}#{conn.request_path}" rel="self" type="application/rss+xml" />
        <language>en</language>
        #{items}
      </channel>
    </rss>
    """

    conn |> put_resp_content_type("application/rss+xml") |> send_resp(200, feed)
  end

  defp atom_entry(post, conn) do
    """
      <entry>
        <id>#{post_url(post, conn)}</id>
        <title>#{escape(post.title)}</title>
        <updated>#{DateTime.to_iso8601(post.updated_at)}</updated>
        <published>#{DateTime.to_iso8601(post.published_at)}</published>
        <link href="#{post_url(post, conn)}" />
        <summary>#{escape(post.excerpt || "")}</summary>
        <content type="html">#{post |> body_html() |> escape()}</content>
      </entry>
    """
  end

  defp rss_item(post, conn) do
    """
      <item>
        <title>#{escape(post.title)}</title>
        <link>#{post_url(post, conn)}</link>
        <guid>#{post_url(post, conn)}</guid>
        <pubDate>#{Calendar.strftime(post.published_at, "%a, %d %b %Y %H:%M:%S %z")}</pubDate>
        <description>#{escape(post.excerpt || "")}</description>
        <content:encoded><![CDATA[#{post |> body_html() |> cdata()}]]></content:encoded>
      </item>
    """
  end

  defp body_html(post),
    do: post.body |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  defp latest_updated_at(posts, site) do
    Enum.reduce(posts, site.updated_at, fn post, updated_at ->
      if DateTime.after?(post.updated_at, updated_at), do: post.updated_at, else: updated_at
    end)
  end

  defp post_url(post, conn), do: "#{origin(conn)}/blog/#{post.slug}/"

  defp origin(conn),
    do:
      "#{conn.scheme}://#{conn.host}" <> if(conn.port in [80, 443], do: "", else: ":#{conn.port}")

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  defp cdata(value), do: String.replace(value, "]]>", "]]]]><![CDATA[>")
end
