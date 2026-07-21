defmodule GesttaltWeb.SiteSettingsControllerTest do
  use GesttaltWeb.ConnCase, async: true

  alias Gesttalt.Sites

  setup :register_and_log_in_user

  test "shows ownership and routing instructions for a pending custom domain", %{
    conn: conn,
    user: user
  } do
    {:ok, site} = Sites.ensure_site_for_user(user)
    {:ok, _site} = Sites.update_billing(site, %{subscription_status: :trialing})
    {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "writing.example.com"})

    response = conn |> get(~p"/admin/settings") |> html_response(200)

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
