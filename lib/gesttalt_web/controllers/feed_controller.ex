defmodule GesttaltWeb.FeedController do
  use GesttaltWeb, :controller

  alias Gesttalt.Publishing

  def index(%{assigns: %{current_site: site}} = conn, _params) do
    posts = Publishing.list_published_posts(site)
    updated_at = posts |> List.first() |> updated_at()
    entries = Enum.map_join(posts, "\n", &entry(&1, conn))

    feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <id>#{origin(conn)}/</id>
      <title>#{escape(site.name)}</title>
      <updated>#{DateTime.to_iso8601(updated_at)}</updated>
      <link href="#{origin(conn)}/blog/feed.xml" rel="self" />
      <link href="#{origin(conn)}/" />
      #{entries}
    </feed>
    """

    conn |> put_resp_content_type("application/atom+xml") |> send_resp(200, feed)
  end

  defp entry(post, conn) do
    """
      <entry>
        <id>#{origin(conn)}/blog/#{post.slug}/</id>
        <title>#{escape(post.title)}</title>
        <updated>#{DateTime.to_iso8601(post.updated_at)}</updated>
        <published>#{DateTime.to_iso8601(post.published_at)}</published>
        <link href="#{origin(conn)}/blog/#{post.slug}/" />
        <summary>#{escape(post.excerpt || "")}</summary>
      </entry>
    """
  end

  defp updated_at(nil), do: DateTime.utc_now()
  defp updated_at(post), do: post.updated_at

  defp origin(conn),
    do:
      "#{conn.scheme}://#{conn.host}" <> if(conn.port in [80, 443], do: "", else: ":#{conn.port}")

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
