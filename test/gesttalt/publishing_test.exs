defmodule Gesttalt.PublishingTest do
  use Gesttalt.DataCase, async: true

  import Gesttalt.AccountsFixtures
  import Gesttalt.PublishingFixtures

  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Idea
  alias Gesttalt.Publishing.Post

  setup do
    %{site: site_fixture()}
  end

  test "lists only posts owned by the requested publication", %{site: site} do
    post = post_fixture(%{site: site})
    _other_post = post_fixture()
    assert Publishing.list_posts(site) == [post]
  end

  test "lists posts from the most to the least recent publication date", %{site: site} do
    older =
      post_fixture(%{
        site: site,
        status: :published,
        published_at: ~U[2018-01-28 12:00:00Z],
        title: "Older"
      })

    newer =
      post_fixture(%{
        site: site,
        status: :published,
        published_at: ~U[2024-11-19 12:00:00Z],
        title: "Newer"
      })

    assert Enum.map(Publishing.list_posts(site), & &1.id) == [newer.id, older.id]
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

  test "paginates published posts from newest to oldest", %{site: site} do
    posts =
      Enum.map(1..21, fn index ->
        post_fixture(%{
          site: site,
          title: "Post #{index}",
          status: :published,
          published_at: DateTime.add(~U[2026-01-01 00:00:00Z], index, :day)
        })
      end)

    {first_page, first_meta} = Publishing.paginate_published_posts(site, 1)
    {second_page, second_meta} = Publishing.paginate_published_posts(site, 2)
    expected_first_page_ids = posts |> Enum.reverse() |> Enum.take(20) |> Enum.map(& &1.id)

    assert Enum.map(first_page, & &1.id) == expected_first_page_ids
    assert Enum.map(second_page, & &1.id) == [hd(posts).id]
    assert first_meta.current_page == 1
    assert first_meta.page_size == 20
    assert first_meta.total_count == 21
    assert first_meta.total_pages == 2
    assert first_meta.has_next_page?
    assert second_meta.current_page == 2
    assert second_meta.has_previous_page?
    refute second_meta.has_next_page?
  end

  test "deletes a post", %{site: site} do
    post = post_fixture(%{site: site})
    assert {:ok, %Post{}} = Publishing.delete_post(post)
    assert Publishing.get_post(site, post.id) == nil
  end

  test "returns a changeset", %{site: site} do
    assert %Ecto.Changeset{} = site |> post_fixture_for_site() |> Publishing.change_post()
  end

  test "creates, updates, and deletes an idea within its publication", %{site: site} do
    assert {:ok, %Idea{} = idea} =
             Publishing.create_idea(site, %{
               title: "Ask about turning points",
               notes: "Start with 2018."
             })

    assert Publishing.list_ideas(site) == [idea]
    assert Publishing.get_idea(site, idea.id) == idea

    assert {:ok, updated_idea} = Publishing.update_idea(idea, %{notes: "Start with 2019."})
    assert updated_idea.notes == "Start with 2019."
    assert {:ok, %Idea{}} = Publishing.delete_idea(updated_idea)
    assert Publishing.get_idea(site, idea.id) == nil
  end

  test "does not expose ideas from another publication", %{site: site} do
    other_site = site_fixture()
    {:ok, idea} = Publishing.create_idea(other_site, %{title: "Private prompt"})

    assert Publishing.list_ideas(site) == []
    assert Publishing.get_idea(site, idea.id) == nil
  end

  defp post_fixture_for_site(site), do: post_fixture(%{site: site})
end
