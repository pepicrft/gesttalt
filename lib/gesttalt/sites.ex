defmodule Gesttalt.Sites do
  @moduledoc "The tenant boundary for publications, domains, themes, and media."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Gesttalt.Accounts.User
  alias Gesttalt.MediaStorage
  alias Gesttalt.Repo
  alias Gesttalt.Sites.{Domain, Image, Site, Theme, ThemeDefaults}

  @platform_host "gesttalt.org"

  def platform_host, do: Application.get_env(:gesttalt, :platform_host, @platform_host)

  def custom_domain_target,
    do: Application.get_env(:gesttalt, :custom_domain_target, "domains.#{platform_host()}")

  def custom_domain_ipv4_addresses,
    do: dns_records(custom_domain_target(), :a) |> Enum.map(&format_ipv4_address/1)

  def list_sites, do: Repo.all(from site in Site, order_by: [asc: site.name])

  def get_site!(id), do: Site |> Repo.get!(id) |> Repo.preload([:domains, :theme])

  def get_site(id), do: Site |> Repo.get(id) |> preload_site()

  def get_site_for_user(%User{id: user_id}) do
    Site |> Repo.get_by(user_id: user_id) |> preload_site()
  end

  def get_site_for_user!(%User{} = user) do
    get_site_for_user(user) || raise Ecto.NoResultsError, queryable: Site
  end

  def ensure_site_for_user(%User{} = user) do
    case get_site_for_user(user) do
      %Site{} = site -> {:ok, site}
      nil -> create_default_site(user)
    end
  end

  def create_default_site(%User{} = user) do
    base_handle = user.email |> String.split("@") |> hd() |> normalize_handle()
    handle = available_handle(base_handle)

    Multi.new()
    |> Multi.insert(
      :site,
      Site.changeset(%Site{}, %{
        user_id: user.id,
        name: display_name(user.email),
        handle: handle,
        tagline: "Independent writing, published thoughtfully."
      })
    )
    |> Multi.insert(:domain, fn %{site: site} ->
      Domain.changeset(%Domain{}, %{
        site_id: site.id,
        hostname: "#{handle}.#{platform_host()}",
        kind: :subdomain,
        status: :active,
        verification_token: token(),
        verified_at: now()
      })
    end)
    |> Multi.insert(:theme, fn %{site: site} ->
      Theme.changeset(%Theme{}, Map.put(ThemeDefaults.attrs(), :site_id, site.id))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{site: site}} -> {:ok, get_site!(site.id)}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def update_site(%Site{} = site, attrs) do
    site |> Site.changeset(attrs) |> Repo.update()
  end

  def get_site_by_stripe_customer(customer_id) when is_binary(customer_id),
    do: Repo.get_by(Site, stripe_customer_id: customer_id)

  def get_site_by_stripe_customer(_customer_id), do: nil

  def update_billing(%Site{} = site, attrs),
    do: site |> Site.billing_changeset(attrs) |> Repo.update()

  def get_site_by_handle(handle) when is_binary(handle),
    do: Site |> Repo.get_by(handle: handle) |> preload_site()

  @doc """
  Grants Publisher features to a site without a Stripe subscription.

  Meant to be run by an operator, either from `iex` or through `Gesttalt.Release.comp_site/1`.
  """
  def comp_site(handle) when is_binary(handle) do
    case get_site_by_handle(handle) do
      nil -> {:error, :not_found}
      %Site{} = site -> update_billing(site, %{subscription_status: :comped})
    end
  end

  @doc "Takes a complimentary site back to the free plan. Sites paying through Stripe are left alone."
  def uncomp_site(handle) when is_binary(handle) do
    case get_site_by_handle(handle) do
      nil ->
        {:error, :not_found}

      %Site{subscription_status: :comped} = site ->
        update_billing(site, %{subscription_status: :inactive})

      %Site{} ->
        {:error, :not_comped}
    end
  end

  def get_site_by_host(host) when is_binary(host) do
    hostname = normalize_host(host)

    Domain
    |> where([domain], domain.hostname == ^hostname and domain.status == :active)
    |> join(:inner, [domain], site in assoc(domain, :site))
    |> preload([domain, site], site: {site, [:theme, :domains]})
    |> Repo.one()
    |> case do
      %Domain{site: site} -> site
      nil -> nil
    end
  end

  def platform_host?(host),
    do: normalize_host(host) in [platform_host(), "www.#{platform_host()}", "localhost"]

  def list_domains(%Site{id: site_id}) do
    Repo.all(
      from domain in Domain, where: domain.site_id == ^site_id, order_by: [asc: domain.hostname]
    )
  end

  def add_custom_domain(%Site{id: site_id}, attrs) do
    attrs = Map.put(attrs, key_for(attrs, :site_id), site_id)
    attrs = Map.put_new(attrs, key_for(attrs, :verification_token), token())

    %Domain{}
    |> Domain.changeset(attrs)
    |> Ecto.Changeset.put_change(:kind, :custom)
    |> Ecto.Changeset.put_change(:status, :pending)
    |> Repo.insert()
  end

  def verify_domain(%Site{} = site, id, dns_lookup \\ &dns_records/2) do
    domain = Repo.get_by!(Domain, id: id, site_id: site.id)
    expected = "gesttalt-domain=#{domain.verification_token}"

    cond do
      expected not in dns_lookup.("_gesttalt.#{domain.hostname}", :txt) ->
        {:error, :verification_record_not_found}

      not domain_routes_to?(domain.hostname, custom_domain_target(), dns_lookup) ->
        {:error, :routing_record_not_found}

      true ->
        domain
        |> Domain.changeset(%{status: :active, verified_at: now()})
        |> Repo.update()
    end
  end

  def delete_domain(%Site{} = site, id) do
    case Repo.get_by(Domain, id: id, site_id: site.id, kind: :custom) do
      %Domain{} = domain -> Repo.delete(domain)
      nil -> {:error, :not_found}
    end
  end

  def get_theme!(%Site{id: site_id}), do: Repo.get_by!(Theme, site_id: site_id)

  def update_theme(%Site{} = site, attrs) do
    site |> get_theme!() |> Theme.changeset(attrs) |> Repo.update()
  end

  def list_images(%Site{id: site_id}) do
    Repo.all(
      from image in Image, where: image.site_id == ^site_id, order_by: [desc: image.inserted_at]
    )
  end

  def get_image!(%Site{id: site_id}, id), do: Repo.get_by!(Image, id: id, site_id: site_id)

  def store_image(%Site{} = site, %Plug.Upload{} = upload, alt_text \\ nil) do
    content_type = upload.content_type || MIME.from_path(upload.filename)
    extension = upload.filename |> Path.extname() |> String.downcase()
    storage_key = account_storage_key(site, "#{Ecto.UUID.generate()}#{extension}")

    attrs = %{
      site_id: site.id,
      filename: Path.basename(upload.filename),
      storage_key: storage_key,
      content_type: content_type,
      byte_size: File.stat!(upload.path).size,
      alt_text: alt_text
    }

    changeset = Image.changeset(%Image{}, attrs)

    if changeset.valid? do
      with {:ok, body} <- File.read(upload.path),
           :ok <- MediaStorage.put(storage_key, body, content_type),
           {:ok, image} <- Repo.insert(changeset) do
        {:ok, image}
      else
        {:error, reason} ->
          MediaStorage.delete(storage_key)
          {:error, reason}
      end
    else
      {:error, changeset}
    end
  end

  def delete_image(%Site{} = site, id) do
    image = get_image!(site, id)

    with {:ok, image} <- Repo.delete(image) do
      MediaStorage.delete(image.storage_key)
      {:ok, image}
    end
  end

  def fetch_image(%Image{} = image) do
    case MediaStorage.get(image.storage_key) do
      {:ok, body} -> {:ok, body}
      {:error, :not_found} -> restore_legacy_image(image)
      {:error, reason} -> {:error, reason}
    end
  end

  def migrate_legacy_images do
    if MediaStorage.object_storage?() do
      Image
      |> Repo.all()
      |> Repo.preload(:site)
      |> Enum.reduce(%{migrated: 0, skipped: 0, failed: []}, &migrate_legacy_image/2)
    else
      %{migrated: 0, skipped: 0, failed: []}
    end
  end

  def image_url(%Image{id: id, filename: filename}), do: "/media/#{id}/#{URI.encode(filename)}"

  defp restore_legacy_image(%Image{} = image) do
    with {:ok, body} <- MediaStorage.read_legacy(image),
         :ok <- MediaStorage.put(image.storage_key, body, image.content_type) do
      _ = MediaStorage.delete_legacy(image.storage_key)
      {:ok, body}
    end
  end

  defp migrate_legacy_image(%Image{} = image) do
    original_key = image.storage_key
    target_key = account_storage_key(image.site, Path.basename(original_key))

    with {:ok, body} <- MediaStorage.read_legacy(original_key),
         :ok <- MediaStorage.put(target_key, body, image.content_type),
         {:ok, image} <- image |> Ecto.Changeset.change(storage_key: target_key) |> Repo.update() do
      _ = MediaStorage.delete_legacy(original_key)
      {:ok, image}
    else
      {:error, reason} = error ->
        if reason != :not_found, do: MediaStorage.delete(target_key)
        error
    end
  end

  defp migrate_legacy_image(image, result) do
    case migrate_legacy_image(image) do
      {:ok, _image} -> Map.update!(result, :migrated, &(&1 + 1))
      {:error, :not_found} -> Map.update!(result, :skipped, &(&1 + 1))
      {:error, reason} -> Map.update!(result, :failed, &[{image.id, reason} | &1])
    end
  end

  defp account_storage_key(%Site{} = site, object_name) do
    "accounts/#{site.user_id}/sites/#{site.id}/#{object_name}"
  end

  defp preload_site(nil), do: nil
  defp preload_site(site), do: Repo.preload(site, [:domains, :theme])

  defp available_handle(base, attempt \\ 0) do
    candidate = if attempt == 0, do: base, else: "#{base}-#{attempt + 1}"

    if Repo.exists?(from site in Site, where: site.handle == ^candidate),
      do: available_handle(base, attempt + 1),
      else: candidate
  end

  defp display_name(email) do
    email
    |> String.split("@")
    |> hd()
    |> String.replace(~r/[._-]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp normalize_handle(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 32)
    |> case do
      value when byte_size(value) >= 2 -> value
      value -> value <> "-site"
    end
  end

  defp normalize_host(host) do
    host |> String.split(":") |> hd() |> Domain.normalize()
  end

  defp dns_records(hostname, type) do
    hostname
    |> String.to_charlist()
    |> :inet_res.lookup(:in, type)
    |> Enum.map(&normalize_dns_record(type, &1))
  rescue
    _error -> []
  end

  defp normalize_dns_record(:txt, record),
    do: record |> IO.iodata_to_binary() |> String.trim_trailing(".")

  defp normalize_dns_record(_type, record), do: record

  defp domain_routes_to?(hostname, target, dns_lookup) do
    address_records_route_to?(hostname, Domain.normalize(target), dns_lookup)
  end

  defp address_records_route_to?(hostname, target, dns_lookup) do
    address_pairs =
      Enum.map([:a, :aaaa], fn type ->
        {MapSet.new(dns_lookup.(hostname, type)), MapSet.new(dns_lookup.(target, type))}
      end)

    Enum.any?(address_pairs, fn {domain_addresses, _target_addresses} ->
      MapSet.size(domain_addresses) > 0
    end) and
      Enum.all?(address_pairs, fn {domain_addresses, target_addresses} ->
        MapSet.size(domain_addresses) == 0 or MapSet.subset?(domain_addresses, target_addresses)
      end)
  end

  defp format_ipv4_address({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp token, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp key_for(attrs, key),
    do: if(Enum.any?(Map.keys(attrs), &is_binary/1), do: Atom.to_string(key), else: key)
end
