defmodule GesttaltWeb.AnalyticsControllerTest do
  use GesttaltWeb.ConnCase, async: true

  import Gesttalt.AccountsFixtures

  alias Gesttalt.Analytics

  setup do
    site = site_fixture()
    host = site.domains |> List.first() |> Map.fetch!(:hostname)
    %{host: host, site: site}
  end

  test "records a public page view without an authenticated session", %{
    conn: conn,
    host: host,
    site: site
  } do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("cf-ipcountry", "ES")
      |> Map.put(:host, host)
      |> post(~p"/analytics/pageview", %{path: "/blog/a-post"})

    assert response(conn, 204) == ""
    assert Analytics.summary(site).top_pages == [%{path: "/blog/a-post", views: 1}]

    assert Analytics.summary(site).locations == [
             %{country: "ES", label: "Spain", latitude: 40, longitude: -4, views: 1}
           ]
  end

  test "rejects malformed page-view payloads", %{conn: conn, host: host} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> Map.put(:host, host)
      |> post(~p"/analytics/pageview", %{path: "blog/a-post"})

    assert response(conn, 422) == ""
  end
end
