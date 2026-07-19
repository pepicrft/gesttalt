defmodule GesttaltWeb.PageControllerTest do
  use GesttaltWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = conn |> Map.put(:host, "gesttalt.test") |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "A simple blogging platform for the agentic world."
    assert html =~ ~s(href="/legal-notice")
    assert html =~ ~s(href="/privacy")
    assert html =~ ~s(href="/terms")
    assert html =~ ~s(href="/withdrawal")
    assert html =~ ~s(href="/cancel")
    assert html =~ ~s(href="/report-illegal-content")
    assert html =~ ~s(href="/sitemap.xml")
  end

  test "GET public legal pages", %{conn: conn} do
    pages = [
      {~p"/legal-notice", "Legal notice"},
      {~p"/privacy", "Privacy policy"},
      {~p"/terms", "Terms of service"},
      {~p"/withdrawal", "Right of withdrawal"},
      {~p"/cancel", "Cancel a subscription"},
      {~p"/report-illegal-content", "Report illegal content"}
    ]

    for {path, heading} <- pages do
      response = conn |> recycle() |> get(path) |> html_response(200)

      assert response =~ heading
      assert response =~ "Pre-launch draft."
    end

    legal_notice = conn |> recycle() |> get(~p"/legal-notice") |> html_response(200)

    assert legal_notice =~ "Pedro Piñera"
    assert legal_notice =~ "hola@pepicrft.me"
    assert legal_notice =~ "Sole proprietor"
    refute legal_notice =~ "Commercial register"
  end

  test "GET /sitemap.xml", %{conn: conn} do
    conn = get(conn, ~p"/sitemap.xml")

    assert response_content_type(conn, :xml) =~ "application/xml"
    body = response(conn, 200)
    base_url = GesttaltWeb.Endpoint.url()

    assert body =~ "<urlset"
    assert body =~ "<loc>#{base_url}/</loc>"
    assert body =~ "<loc>#{base_url}/privacy</loc>"
    assert body =~ "<loc>#{base_url}/report-illegal-content</loc>"
  end
end
