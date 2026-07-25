defmodule GesttaltWeb.ChangelogFeedController do
  use GesttaltWeb, :controller

  alias Gesttalt.Changelog

  def atom(conn, _params) do
    entries = Changelog.list()
    updated_at = entries |> List.first() |> Changelog.published_at()
    rendered_entries = Enum.map_join(entries, "\n", &atom_entry(&1, conn))

    feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <id>#{origin(conn)}/changelog</id>
      <title>Gesttalt changelog</title>
      <subtitle>New Gesttalt capabilities, improvements, and product updates.</subtitle>
      <updated>#{DateTime.to_iso8601(updated_at)}</updated>
      <link href="#{origin(conn)}/changelog/atom.xml" rel="self" type="application/atom+xml" />
      <link href="#{origin(conn)}/changelog" />
      #{rendered_entries}
    </feed>
    """

    conn |> put_resp_content_type("application/atom+xml") |> send_resp(:ok, feed)
  end

  def rss(conn, _params) do
    entries = Changelog.list()
    updated_at = entries |> List.first() |> Changelog.published_at()
    rendered_items = Enum.map_join(entries, "\n", &rss_item(&1, conn))

    feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>Gesttalt changelog</title>
        <link>#{origin(conn)}/changelog</link>
        <description>New Gesttalt capabilities, improvements, and product updates.</description>
        <atom:link href="#{origin(conn)}#{conn.request_path}" rel="self" type="application/rss+xml" />
        <language>en</language>
        <lastBuildDate>#{rss_date(updated_at)}</lastBuildDate>
        #{rendered_items}
      </channel>
    </rss>
    """

    conn |> put_resp_content_type("application/rss+xml") |> send_resp(:ok, feed)
  end

  defp atom_entry(entry, conn) do
    published_at = Changelog.published_at(entry)

    """
      <entry>
        <id>#{entry_url(entry, conn)}</id>
        <title>#{escape(entry.title)}</title>
        <updated>#{DateTime.to_iso8601(published_at)}</updated>
        <published>#{DateTime.to_iso8601(published_at)}</published>
        <link href="#{entry_url(entry, conn)}" />
        <summary>#{escape(entry.summary)}</summary>
        <content type="html">#{entry |> body_html() |> escape()}</content>
      </entry>
    """
  end

  defp rss_item(entry, conn) do
    """
      <item>
        <title>#{escape(entry.title)}</title>
        <link>#{entry_url(entry, conn)}</link>
        <guid>#{entry_url(entry, conn)}</guid>
        <pubDate>#{entry |> Changelog.published_at() |> rss_date()}</pubDate>
        <description>#{escape(entry.summary)}</description>
        <content:encoded><![CDATA[#{entry |> body_html() |> cdata()}]]></content:encoded>
      </item>
    """
  end

  defp body_html(entry),
    do: entry |> Changelog.body_html() |> Phoenix.HTML.safe_to_string()

  defp entry_url(entry, conn),
    do: "#{origin(conn)}/changelog#changelog-entry-#{entry.slug}"

  defp origin(conn),
    do:
      "#{conn.scheme}://#{conn.host}" <> if(conn.port in [80, 443], do: "", else: ":#{conn.port}")

  defp rss_date(date_time), do: Calendar.strftime(date_time, "%a, %d %b %Y %H:%M:%S %z")
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  defp cdata(value), do: String.replace(value, "]]>", "]]]]><![CDATA[>")
end
