defmodule Gesttalt.AccountDeletionTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountDeletion
  alias Gesttalt.Accounts
  alias Gesttalt.Repo
  alias Gesttalt.Sites
  alias Gesttalt.Sites.Image

  import Gesttalt.AccountsFixtures

  defmodule Storage do
    def delete(storage_key) do
      send(self(), {:deleted, storage_key})
      :ok
    end

    def delete_legacy(storage_key) do
      send(self(), {:deleted_legacy, storage_key})
      :ok
    end
  end

  test "removes stored media before deleting the account and publication records" do
    user = user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)

    image =
      Repo.insert!(%Image{
        site_id: site.id,
        filename: "photo.jpg",
        storage_key: "accounts/#{user.id}/photo.jpg",
        content_type: "image/jpeg",
        byte_size: 100
      })

    assert :ok = AccountDeletion.delete(user.id, Storage)
    assert_received {:deleted, "accounts/" <> _rest}
    assert_received {:deleted_legacy, "accounts/" <> _rest}
    refute Accounts.get_user_by_email(user.email)
    refute Repo.get(Image, image.id)
    assert Sites.get_site(site.id) == nil
  end

  test "is idempotent when an account is already gone" do
    assert :ok = AccountDeletion.delete(-1, Storage)
  end
end
