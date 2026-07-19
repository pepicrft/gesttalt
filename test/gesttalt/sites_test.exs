defmodule Gesttalt.SitesTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Sites

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    %{site: site, user: user}
  end

  test "creates a publication, active subdomain, and Liquid theme together", %{site: site} do
    assert site.theme.name == "Paper"
    assert [%{kind: :subdomain, status: :active} = domain] = site.domains
    assert domain.hostname == "#{site.handle}.gesttalt.test"
    assert Sites.get_site_by_host(String.upcase(domain.hostname) <> ":443").id == site.id
  end

  test "returns the same publication when setup is repeated", %{site: site, user: user} do
    assert {:ok, repeated_site} = Sites.ensure_site_for_user(user)
    assert repeated_site.id == site.id
    assert length(Sites.list_sites()) == 1
  end

  test "keeps a custom domain private until it has been verified", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "WRITING.EXAMPLE.COM."})
    assert domain.hostname == "writing.example.com"
    assert domain.status == :pending
    refute Sites.get_site_by_host(domain.hostname)
  end

  test "does not expose another publication through the tenant boundary", %{site: site} do
    another_user = AccountsFixtures.user_fixture()
    {:ok, another_site} = Sites.ensure_site_for_user(another_user)

    refute Sites.get_site_by_host(hd(another_site.domains).hostname).id == site.id
  end
end
