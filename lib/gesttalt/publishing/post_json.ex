defmodule Gesttalt.Publishing.PostJSON do
  @moduledoc "Stable JSON representation of a Gesttalt article."

  alias Gesttalt.Publishing.Post

  @doc "Serializes one article for the publishing interface and Model Context Protocol tools."
  def render(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      slug: post.slug,
      excerpt: post.excerpt,
      body: post.body,
      kind: post.kind,
      status: post.status,
      published_at: post.published_at,
      inserted_at: post.inserted_at,
      updated_at: post.updated_at,
      url: url(post)
    }
  end

  defp url(%Post{status: :published, kind: :post, slug: slug}), do: "/blog/#{slug}/"
  defp url(%Post{status: :published, kind: :page, slug: slug}), do: "/#{slug}/"
  defp url(_post), do: nil
end
