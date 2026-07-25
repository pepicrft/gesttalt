defmodule Gesttalt.Publishing do
  @moduledoc "The tenant-scoped boundary for creating, editing, and reading articles and pages."

  import Ecto.Query, warn: false

  alias Gesttalt.Publishing.Post
  alias Gesttalt.Repo
  alias Gesttalt.Sites.Site

  @published_posts_page_size 20

  @doc "Lists every post for a site, newest first by the date the desk shows."
  def list_posts(%Site{id: site_id}) do
    Post
    |> where([post], post.site_id == ^site_id)
    |> order_by([post], desc: coalesce(post.published_at, post.updated_at))
    |> Repo.all()
  end

  @doc "Lists public articles for a site, newest first."
  def list_published_posts(%Site{id: site_id}) do
    published_query(site_id, :post) |> Repo.all()
  end

  @doc "Lists one page of public articles and its pagination metadata."
  def paginate_published_posts(%Site{id: site_id}, page \\ 1) when is_integer(page) do
    published_query(site_id, :post)
    |> Flop.validate_and_run!(
      %{page: max(page, 1), page_size: @published_posts_page_size},
      for: Post
    )
  end

  @doc "Lists public standalone pages for a site."
  def list_published_pages(%Site{id: site_id}) do
    published_query(site_id, :page) |> Repo.all()
  end

  @doc "Fetches a site-owned post by its database identifier."
  def get_post!(%Site{id: site_id}, id), do: Repo.get_by!(Post, id: id, site_id: site_id)

  @doc "Fetches a site-owned post without raising."
  def get_post(%Site{id: site_id}, id), do: Repo.get_by(Post, id: id, site_id: site_id)

  @doc "Fetches a public post by kind and slug."
  def get_published_post_by_slug!(%Site{id: site_id}, kind, slug) when kind in [:post, :page] do
    now = now()

    Post
    |> where([post], post.site_id == ^site_id)
    |> where([post], post.kind == ^kind)
    |> where([post], post.slug == ^slug)
    |> where([post], post.status == :published)
    |> where([post], post.published_at <= ^now)
    |> Repo.one!()
  end

  @doc "Fetches a site-owned post by slug, including drafts."
  def get_post_by_slug(%Site{id: site_id}, slug),
    do: Repo.get_by(Post, site_id: site_id, slug: slug)

  @doc "Creates a post owned by a site."
  def create_post(%Site{id: site_id}, attrs \\ %{}) do
    attrs = Map.put(attrs, key_for(attrs, :site_id), site_id)

    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a post."
  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  end

  @doc "Publishes a post immediately, unless it has a future publication time."
  def publish_post(%Post{} = post), do: post |> Post.publish_changeset() |> Repo.update()

  @doc "Moves a published post back to drafts."
  def unpublish_post(%Post{} = post), do: post |> Post.unpublish_changeset() |> Repo.update()

  @doc "Permanently deletes a post."
  def delete_post(%Post{} = post), do: Repo.delete(post)

  @doc "Returns a changeset for a post form."
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  defp published_query(site_id, kind) do
    now = now()

    Post
    |> where([post], post.site_id == ^site_id)
    |> where([post], post.kind == ^kind)
    |> where([post], post.status == :published)
    |> where([post], post.published_at <= ^now)
    |> order_by([post], desc: post.published_at, desc: post.id)
  end

  defp key_for(attrs, key) do
    if Enum.any?(Map.keys(attrs), &is_binary/1), do: Atom.to_string(key), else: key
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
