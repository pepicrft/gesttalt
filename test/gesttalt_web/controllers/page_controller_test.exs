defmodule GesttaltWeb.PageControllerTest do
  use GesttaltWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = conn |> Map.put(:host, "gesttalt.test") |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "A blog your agents can run. A publication you own."
    assert html =~ "Manage the whole publication"
    assert html =~ "Everything is free during early access"
    refute html =~ "€5"
    refute html =~ "Upgrade"
    assert html =~ ~s(href="/legal-notice")
    assert html =~ ~s(href="/privacy")
    assert html =~ ~s(href="/terms")
    assert html =~ ~s(href="/withdrawal")
    assert html =~ ~s(href="/cancel")
    assert html =~ ~s(href="/report-illegal-content")
    assert html =~ ~s(href="/sitemap.xml")
  end

  test "GET /docs describes agent registration and dashboard tool parity", %{conn: conn} do
    html = conn |> get(~p"/docs") |> html_response(200)

    assert html =~ ~s(id="agent-registration")
    assert html =~ "/.well-known/oauth-protected-resource/mcp"
    assert html =~ "every publication action available in the dashboard"
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

    assert legal_notice =~ "Pedro Piñera Buendía"
    assert legal_notice =~ "hola@pepicrft.me"
    assert legal_notice =~ "Sole proprietor"
    refute legal_notice =~ "Serviceable address"
    refute legal_notice =~ "Commercial register"

    privacy = conn |> recycle() |> get(~p"/privacy") |> html_response(200)

    assert privacy =~ "Pedro Piñera Buendía"
    refute privacy =~ "Serviceable address"
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
