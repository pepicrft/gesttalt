defmodule GesttaltWeb.SiteSettingsControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "shows ownership and routing instructions for a pending custom domain", %{
    conn: conn,
    user: user
  } do
    {:ok, site} = Sites.ensure_site_for_user(user)

    conn =
      post(conn, ~p"/admin/domains", %{
        "domain" => %{"hostname" => "writing.example.com"}
      })

    assert redirected_to(conn) == ~p"/admin/settings"

    domain =
      site
      |> Sites.list_domains()
      |> Enum.find(&(&1.hostname == "writing.example.com"))

    response = conn |> recycle() |> get(~p"/admin/settings") |> html_response(200)

    assert response =~ "Add both records below"
    assert response =~ "Text (TXT) record"
    assert response =~ "_gesttalt.writing.example.com"
    assert response =~ "gesttalt-domain=#{domain.verification_token}"
    assert response =~ "Canonical Name (CNAME) record"
    assert response =~ "domains.gesttalt.test"
    assert response =~ "Disable proxying until setup finishes"
    refute response =~ "Address (A) record"
  end
end
