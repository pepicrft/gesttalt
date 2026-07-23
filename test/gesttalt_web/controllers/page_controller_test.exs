defmodule GesttaltWeb.PageControllerTest do
  use GesttaltWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = conn |> Map.put(:host, "gesttalt.test") |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ "A blog your agents can run. A publication you own."
    assert html =~ "Manage the whole publication"
    refute html =~ ~r/pricing|payment|free|€|per month|upgrade/i
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
    end

    legal_notice = conn |> recycle() |> get(~p"/legal-notice") |> html_response(200)

    assert legal_notice =~ "Pedro Piñera Buendía"
    assert legal_notice =~ "gesttalt@pepicrft.me"
    assert legal_notice =~ "Sole proprietor"
    assert legal_notice =~ "Serviceable address"
    assert legal_notice =~ "Jessnerstrasse 27a"
    assert legal_notice =~ "10247 Berlin"
    refute legal_notice =~ "Draft pending a publishable address."
    refute legal_notice =~ "Commercial register"

    privacy = conn |> recycle() |> get(~p"/privacy") |> html_response(200)

    assert privacy =~ "Pedro Piñera Buendía"
    assert privacy =~ "Hetzner Online GmbH"
    assert privacy =~ "automatically deleted after 30 days"
    refute privacy =~ "Draft pending a publishable address."
    refute privacy =~ "Serviceable address"

    report = conn |> recycle() |> get(~p"/report-illegal-content") |> html_response(200)
    assert report =~ ~s(id="illegal-content-report-form")
    refute report =~ "Draft pending a publishable address."

    cancellation = conn |> recycle() |> get(~p"/cancel") |> html_response(200)
    assert cancellation =~ "No paid subscription to cancel"
    refute cancellation =~ "Draft pending a publishable address."

    terms = conn |> recycle() |> get(~p"/terms") |> html_response(200)
    assert terms =~ "Jessnerstrasse 27a"
    refute terms =~ "Draft pending a publishable address."

    withdrawal = conn |> recycle() |> get(~p"/withdrawal") |> html_response(200)
    assert withdrawal =~ "Jessnerstrasse 27a"
    refute withdrawal =~ "Draft pending a publishable address."
  end

  test "POST /report-illegal-content records a valid report", %{conn: conn} do
    conn =
      post(conn, ~p"/report-illegal-content", %{
        "illegal_content_report" => %{
          "content_url" => "https://writer.gesttalt.test/blog/reported-post",
          "explanation" =>
            "This page contains a specific threat against an identified person and should be reviewed.",
          "reporter_name" => "Robin Reporter",
          "reporter_email" => "reporter@example.com",
          "good_faith" => "true"
        }
      })

    assert redirected_to(conn) == ~p"/report-illegal-content"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your report was received"
  end

  test "POST /report-illegal-content renders validation errors", %{conn: conn} do
    conn =
      post(conn, ~p"/report-illegal-content", %{
        "illegal_content_report" => %{
          "content_url" => "/relative",
          "explanation" => "Too short",
          "good_faith" => "false"
        }
      })

    response = html_response(conn, 422)
    assert response =~ "must be a complete http or https address"
    assert response =~ "must be confirmed before the report can be submitted"
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
