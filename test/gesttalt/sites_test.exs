defmodule Gesttalt.SitesTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Repo
  alias Gesttalt.Sites
  alias Gesttalt.Sites.{Theme, ThemeDefaults}

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    %{site: site, user: user}
  end

  test "creates a publication with the built-in theme and no stored override", %{site: site} do
    assert site.theme.name == "Paper"
    refute Repo.get_by(Theme, site_id: site.id)
    assert [%{kind: :subdomain, status: :active} = domain] = site.domains
    assert domain.hostname == "#{site.handle}.gesttalt.test"
    assert Sites.get_site_by_host(String.upcase(domain.hostname) <> ":443").id == site.id
  end

  test "takes over the built-in theme when it is customized", %{site: site} do
    assert {:ok, theme} = Sites.update_theme(site, %{name: "Pedro"})

    assert theme.name == "Pedro"
    assert Repo.get_by!(Theme, site_id: site.id).name == "Pedro"
  end

  test "inherits a selected built-in theme until it is customized", %{site: site} do
    assert {:ok, selected_theme} = Sites.select_built_in_theme(site, "darkroom")
    assert selected_theme.inherited
    assert selected_theme.built_in_theme == "darkroom"

    inherited_theme = Sites.get_theme!(site)
    assert inherited_theme.name == "Darkroom"
    assert inherited_theme.variables["colors"]["background"] == "#121211"

    assert {:ok, custom_theme} = Sites.update_theme(site, %{name: "Pedro after dark"})
    refute custom_theme.inherited
    assert custom_theme.name == "Pedro after dark"
    assert custom_theme.variables["colors"]["background"] == "#121211"
  end

  test "rejects an unavailable built-in theme", %{site: site} do
    assert {:error, :not_found} = Sites.select_built_in_theme(site, "unknown")
    refute Repo.get_by(Theme, site_id: site.id)
  end

  test "keeps the Paper type scale across built-in themes" do
    paper_font_sizes = ThemeDefaults.attrs("paper").variables["fontSizes"]

    for %{id: id} <- ThemeDefaults.all() do
      assert ThemeDefaults.attrs(id).variables["fontSizes"] == paper_font_sizes
    end
  end

  test "uses the current built-in theme for an inherited legacy record", %{site: site} do
    inherited_theme =
      %Theme{}
      |> Theme.changeset(Map.put(ThemeDefaults.attrs(), :site_id, site.id))
      |> Ecto.Changeset.put_change(:inherited, true)
      |> Repo.insert!()

    assert Sites.get_theme!(site).inherited
    assert Sites.get_theme!(site).stylesheet =~ "#site-photography"

    assert {:ok, override} = Sites.update_theme(site, %{name: "Pedro"})
    refute override.inherited
    assert override.id == inherited_theme.id
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

  test "requires ownership and routing before activating a custom domain", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "writing.example.com"})

    records = %{
      {"_gesttalt.writing.example.com", :txt} => [
        "gesttalt-domain=#{domain.verification_token}"
      ],
      {"writing.example.com", :cname} => ["domains.gesttalt.test"],
      {"writing.example.com", :a} => [{192, 0, 2, 10}],
      {"domains.gesttalt.test", :a} => [{192, 0, 2, 10}]
    }

    lookup = fn hostname, type -> Map.get(records, {hostname, type}, []) end

    assert {:ok, verified_domain} = Sites.verify_domain(site, domain.id, lookup)
    assert verified_domain.status == :active
    assert verified_domain.verified_at
    assert Sites.get_site_by_host(domain.hostname).id == site.id
  end

  test "rejects a custom domain that proves ownership but routes elsewhere", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "writing.example.com"})

    records = %{
      {"_gesttalt.writing.example.com", :txt} => [
        "gesttalt-domain=#{domain.verification_token}"
      ],
      {"writing.example.com", :a} => [{192, 0, 2, 10}],
      {"domains.gesttalt.test", :a} => [{192, 0, 2, 20}]
    }

    lookup = fn hostname, type -> Map.get(records, {hostname, type}, []) end

    assert {:error, :routing_record_not_found} = Sites.verify_domain(site, domain.id, lookup)
    refute Sites.get_site_by_host(domain.hostname)
  end

  test "rejects a custom domain with an additional address that routes elsewhere", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "writing.example.com"})

    records = %{
      {"_gesttalt.writing.example.com", :txt} => [
        "gesttalt-domain=#{domain.verification_token}"
      ],
      {"writing.example.com", :a} => [{192, 0, 2, 10}, {192, 0, 2, 20}],
      {"domains.gesttalt.test", :a} => [{192, 0, 2, 10}]
    }

    lookup = fn hostname, type -> Map.get(records, {hostname, type}, []) end

    assert {:error, :routing_record_not_found} = Sites.verify_domain(site, domain.id, lookup)
    refute Sites.get_site_by_host(domain.hostname)
  end

  test "accepts a custom domain routed to the platform address", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "example.com"})

    records = %{
      {"_gesttalt.example.com", :txt} => ["gesttalt-domain=#{domain.verification_token}"],
      {"example.com", :a} => [{192, 0, 2, 10}],
      {"domains.gesttalt.test", :a} => [{192, 0, 2, 10}]
    }

    lookup = fn hostname, type -> Map.get(records, {hostname, type}, []) end

    assert {:ok, verified_domain} = Sites.verify_domain(site, domain.id, lookup)
    assert verified_domain.status == :active
  end

  test "rejects a routed custom domain without proof of ownership", %{site: site} do
    assert {:ok, domain} = Sites.add_custom_domain(site, %{"hostname" => "example.com"})

    records = %{
      {"example.com", :cname} => ["domains.gesttalt.test"]
    }

    lookup = fn hostname, type -> Map.get(records, {hostname, type}, []) end

    assert {:error, :verification_record_not_found} = Sites.verify_domain(site, domain.id, lookup)
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
