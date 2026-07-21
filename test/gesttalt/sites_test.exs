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
    site_count = length(Sites.list_sites())
    assert {:ok, repeated_site} = Sites.ensure_site_for_user(user)
    assert repeated_site.id == site.id
    assert length(Sites.list_sites()) == site_count
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

  test "stores media under the owning account and site", %{site: site, user: user} do
    upload = upload_fixture("account-image.png", "account image")

    assert {:ok, image} = Sites.store_image(site, upload, "Account image")

    assert image.storage_key =~ "accounts/#{user.id}/sites/#{site.id}/"
    assert {:ok, "account image"} = Sites.fetch_image(image)
    assert {:ok, _image} = Sites.delete_image(site, image.id)
    assert {:error, :enoent} = Gesttalt.MediaStorage.get(image.storage_key)
  end

  test "grants and revokes the complimentary Publisher plan by handle", %{site: site} do
    assert {:ok, comped} = Sites.comp_site(site.handle)
    assert comped.subscription_status == :comped
    assert Gesttalt.Plans.available?(comped, :custom_domains)

    assert {:ok, free} = Sites.uncomp_site(site.handle)
    assert free.subscription_status == :inactive
    assert {:error, :not_comped} = Sites.uncomp_site(site.handle)
    assert {:error, :not_found} = Sites.comp_site("no-such-publication")
  end

  defp upload_fixture(filename, contents) do
    path = Path.join(System.tmp_dir!(), "gesttalt-#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end
end
