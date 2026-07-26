defmodule Gesttalt.Photography do
  @moduledoc "The tenant-scoped photography feed."

  import Ecto.Query, warn: false

  alias Gesttalt.Photography.Photo
  alias Gesttalt.Repo
  alias Gesttalt.Sites
  alias Gesttalt.Sites.Site

  def list_photos(%Site{id: site_id}) do
    Repo.all(
      from photo in Photo,
        where: photo.site_id == ^site_id,
        order_by: [desc: photo.inserted_at],
        preload: [:image]
    )
  end

  def list_published_photos(%Site{id: site_id}) do
    now = DateTime.utc_now()

    Repo.all(
      from photo in Photo,
        where:
          photo.site_id == ^site_id and photo.status == :published and
            photo.published_at <= ^now,
        order_by: [desc: photo.published_at, desc: photo.id],
        preload: [:image]
    )
  end

  def get_photo(%Site{id: site_id}, id) do
    Photo
    |> Repo.get_by(id: id, site_id: site_id)
    |> preload_image()
  end

  def fetch_photo(%Site{} = site, id) do
    case get_photo(site, id) do
      nil -> {:error, :not_found}
      photo -> {:ok, photo}
    end
  end

  def create_photo(%Site{} = site, %Plug.Upload{} = upload, attrs) when is_map(attrs) do
    alt_text = value(attrs, :alt_text)

    with :ok <- validate_alt_text(alt_text),
         {:ok, image} <- Sites.store_image(site, upload, alt_text) do
      insert_photo(site, image, attrs)
    end
  end

  def update_photo(%Photo{} = photo, attrs) do
    photo
    |> Photo.changeset(Map.take(attrs, [:caption, "caption"]))
    |> Repo.update()
    |> preload_result()
  end

  def publish_photo(%Photo{} = photo) do
    photo
    |> Photo.changeset(%{status: :published})
    |> Repo.update()
    |> preload_result()
  end

  def unpublish_photo(%Photo{} = photo) do
    photo
    |> Photo.changeset(%{status: :draft})
    |> Repo.update()
    |> preload_result()
  end

  def delete_photo(%Site{} = site, id) do
    with {:ok, photo} <- fetch_photo(site, id),
         {:ok, _image} <- Sites.delete_image(site, photo.image_id),
         do: {:ok, photo}
  end

  defp preload_image(nil), do: nil
  defp preload_image(photo), do: Repo.preload(photo, :image)

  defp preload_result({:ok, photo}), do: {:ok, Repo.preload(photo, :image)}
  defp preload_result({:error, _reason} = error), do: error

  defp insert_photo(site, image, attrs) do
    attrs =
      attrs
      |> Map.drop([:alt_text, "alt_text", :file, "file"])
      |> put_owner(:site_id, site.id)
      |> put_owner(:image_id, image.id)

    case %Photo{} |> Photo.changeset(attrs) |> Repo.insert() do
      {:ok, photo} ->
        {:ok, Repo.preload(photo, :image)}

      {:error, reason} ->
        _result = Sites.delete_image(site, image.id)
        {:error, reason}
    end
  end

  defp put_owner(attrs, key, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: Map.put(attrs, Atom.to_string(key), value),
      else: Map.put(attrs, key, value)
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp validate_alt_text(value) when is_binary(value) do
    if String.trim(value) == "", do: {:error, :alt_text_required}, else: :ok
  end

  defp validate_alt_text(_value), do: {:error, :alt_text_required}
end
