defmodule Gesttalt.PublicMarkdown do
  @moduledoc "Produces the public, agent-readable Markdown representations of a publication."

  alias Gesttalt.Publishing.Post
  alias Gesttalt.Sites.Site

  def home(%Site{} = site, posts) do
    ["# #{site.name}", site.tagline, site.description, post_links("Latest writing", posts)]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  def archive(%Site{} = site, posts, pagination) do
    page = Map.get(pagination, :current_page, 1)
    pages = Map.get(pagination, :total_pages, 1)

    ["# Writing from #{site.name}", post_links(nil, posts), "Page #{page} of #{max(pages, 1)}."]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  def article(%Post{} = post), do: document(post)
  def page(%Post{} = page), do: document(page)

  def photography(%Site{} = site, photos) do
    entries =
      Enum.map_join(photos, "\n\n", fn photo ->
        image = photo.image
        caption = if blank?(photo.caption), do: image.alt_text, else: photo.caption
        "![#{image.alt_text}](/media/#{image.id}/#{image.filename})\n\n#{caption}"
      end)

    ["# Photography from #{site.name}", entries]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  def index(%Site{} = site, pages, posts) do
    sections =
      [
        "# #{site.name}",
        site.tagline,
        "## Pages\n\n" <> link_list(pages, &"/#{&1.slug}.md"),
        "## Writing\n\n" <> link_list(posts, &"/blog/#{&1.slug}.md"),
        "## Other\n\n- [Photography](/photography.md)"
      ]
      |> Enum.reject(&blank?/1)

    Enum.join(sections, "\n\n") <> "\n"
  end

  defp document(%Post{} = post) do
    document =
      ["# #{post.title}", post.excerpt, post.body, tags(post.tags)]
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n\n")

    document <> "\n"
  end

  defp post_links(heading, posts) do
    links = link_list(posts, &"/blog/#{&1.slug}.md")
    if heading, do: "## #{heading}\n\n#{links}", else: links
  end

  defp link_list(posts, path) do
    Enum.map_join(posts, "\n", fn post ->
      summary = if blank?(post.excerpt), do: "", else: ": #{post.excerpt}"
      "- [#{post.title}](#{path.(post)})#{summary}"
    end)
  end

  defp tags([]), do: nil
  defp tags(tags), do: "Tags: " <> Enum.map_join(tags, ", ", &"`#{&1}`")
  defp blank?(value), do: value in [nil, ""]
end
