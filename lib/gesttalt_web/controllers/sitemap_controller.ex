defmodule GesttaltWeb.SitemapController do
  use GesttaltWeb, :controller

  def show(conn, _params) do
    base_url = GesttaltWeb.Endpoint.url()

    paths = [
      ~p"/",
      ~p"/docs",
      ~p"/changelog",
      ~p"/legal-notice",
      ~p"/privacy",
      ~p"/terms",
      ~p"/withdrawal",
      ~p"/cancel",
      ~p"/report-illegal-content"
    ]

    entries =
      Enum.map_join(paths, "\n", fn path ->
        "  <url><loc>#{base_url}#{path}</loc></url>"
      end)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{entries}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(:ok, body)
  end
end
