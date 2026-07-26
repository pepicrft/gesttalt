defmodule Gesttalt.PhotographyTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Photography
  alias Gesttalt.Sites

  setup do
    site = AccountsFixtures.site_fixture()
    %{site: site}
  end

  test "keeps drafts private until they are published", %{site: site} do
    upload = upload_fixture("morning.png", "morning light")

    assert {:ok, photo} =
             Photography.create_photo(site, upload, %{
               alt_text: "Morning light across a wooden table",
               caption: "Before the house woke up.",
               status: :draft
             })

    assert photo.status == :draft
    assert photo.published_at == nil
    assert Photography.list_published_photos(site) == []

    assert {:ok, published} = Photography.publish_photo(photo)
    assert published.status == :published
    assert published.published_at
    assert [listed] = Photography.list_published_photos(site)
    assert listed.id == photo.id

    assert {:ok, draft} = Photography.unpublish_photo(published)
    assert draft.status == :draft
    assert draft.published_at == nil
    assert Photography.list_published_photos(site) == []
  end

  test "deletes the feed entry and its stored image together", %{site: site} do
    upload = upload_fixture("lake.png", "lake")

    assert {:ok, photo} =
             Photography.create_photo(site, upload, %{
               alt_text: "A still lake beneath a cloudy sky",
               status: :published
             })

    storage_key = photo.image.storage_key
    assert {:ok, _photo} = Photography.delete_photo(site, photo.id)
    refute Photography.get_photo(site, photo.id)
    assert {:error, :enoent} = Gesttalt.MediaStorage.get(storage_key)
  end

  test "requires alternative text and keeps photos inside their publication", %{site: site} do
    upload = upload_fixture("path.png", "path")

    assert {:error, :alt_text_required} =
             Photography.create_photo(site, upload, %{caption: "No description"})

    other_site = AccountsFixtures.site_fixture()

    assert {:ok, photo} =
             Photography.create_photo(other_site, upload, %{
               alt_text: "A path between tall trees"
             })

    refute Photography.get_photo(site, photo.id)
    assert {:error, :not_found} = Photography.fetch_photo(site, photo.id)
    assert {:ok, _photo} = Photography.delete_photo(other_site, photo.id)
    assert Sites.list_images(site) == []
  end

  defp upload_fixture(filename, contents) do
    path = Path.join(System.tmp_dir!(), "gesttalt-photo-#{Ecto.UUID.generate()}-#{filename}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end
end
