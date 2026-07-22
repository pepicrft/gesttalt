defmodule GesttaltWeb.SiteControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.AccountsFixtures

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
    assert get_resp_header(conn, "vary") == ["cookie"]
  end

  test "does not show publication controls to anonymous visitors", %{conn: conn, host: host} do
    conn = conn |> Map.put(:host, host) |> get(~p"/")
    body = html_response(conn, 200)

    refute body =~ ~s(id="gesttalt-owner-controls")
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(conn, "vary") == ["cookie"]
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
end
