defmodule Gesttalt.PublishingTest do
  use Gesttalt.DataCase, async: true

  import Gesttalt.AccountsFixtures
  import Gesttalt.PublishingFixtures

  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Post

  setup do
    %{site: site_fixture()}
  end

  test "lists only posts owned by the requested publication", %{site: site} do
    post = post_fixture(%{site: site})
    _other_post = post_fixture()
    assert Publishing.list_posts(site) == [post]
  end

  test "fetches posts through the tenant boundary", %{site: site} do
    post = post_fixture(%{site: site})
    other_site = site_fixture()
    assert Publishing.get_post!(site, post.id) == post
    assert_raise Ecto.NoResultsError, fn -> Publishing.get_post!(other_site, post.id) end
  end

  test "creates a page with a generated slug", %{site: site} do
    assert {:ok, %Post{} = page} =
             Publishing.create_post(site, %{title: "About this place", body: "Hello", kind: :page})

    assert page.slug == "about-this-place"
    assert page.kind == :page
    assert page.status == :draft
  end

  test "rejects invalid content", %{site: site} do
    assert {:error, %Ecto.Changeset{}} = Publishing.create_post(site, %{title: nil, body: nil})
  end

  test "updates and publishes a post", %{site: site} do
    post = post_fixture(%{site: site})

    assert {:ok, post} =
             Publishing.update_post(post, %{title: "A new title", slug: "a-new-title"})

    assert post.title == "A new title"
    assert {:ok, post} = Publishing.publish_post(post)
    assert post.status == :published
    assert Post.published?(post)
    assert Publishing.list_published_posts(site) == [post]
  end

  test "deletes a post", %{site: site} do
    post = post_fixture(%{site: site})
    assert {:ok, %Post{}} = Publishing.delete_post(post)
    assert Publishing.get_post(site, post.id) == nil
  end

  test "returns a changeset", %{site: site} do
    assert %Ecto.Changeset{} = site |> post_fixture_for_site() |> Publishing.change_post()
  end

  defp post_fixture_for_site(site), do: post_fixture(%{site: site})
end
