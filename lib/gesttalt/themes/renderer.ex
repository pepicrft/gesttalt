defmodule Gesttalt.Themes.Renderer do
  @moduledoc "Renders tenant-owned Liquid templates with a stable publishing context."

  alias Gesttalt.Markdown
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Post
  alias Gesttalt.Sites.{Site, Theme}
  alias Gesttalt.Themes.Variables

  def render_index(%Site{} = site, %Theme{} = theme, posts, pages, pagination \\ nil) do
    render(
      theme.index_template,
      base_context(site, theme, pages)
      |> Map.put("posts", Enum.map(posts, &post_context/1))
      |> Map.put("pagination", pagination_context(pagination, length(posts)))
    )
  end

  def render_article(%Site{} = site, %Theme{} = theme, %Post{} = post, pages) do
    render(
      theme.article_template,
      base_context(site, theme, pages) |> Map.put("post", post_context(post))
    )
  end

  def render_page(%Site{} = site, %Theme{} = theme, %Post{} = page, pages) do
    render(
      theme.page_template,
      base_context(site, theme, pages) |> Map.put("page", post_context(page))
    )
  end

  def render_string(template, context) when is_binary(template) and is_map(context),
    do: render(template, context)

  def sample_context(stylesheet \\ "") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    post = %Post{
      title: "A quiet place for lasting words",
      slug: "a-quiet-place",
      excerpt: "A sample article for developing a Gesttalt theme.",
      body:
        "## Hello from your theme\n\nEdit a Liquid template or the stylesheet and the browser reloads.",
      kind: :post,
      status: :published,
      published_at: now
    }

    site = %Site{
      name: "Your publication",
      handle: "preview",
      tagline: "Independent writing, published thoughtfully."
    }

    base_context(site, %Theme{stylesheet: stylesheet, variables: Variables.defaults()}, [])
    |> Map.put("posts", [post_context(post)])
    |> Map.put("post", post_context(post))
    |> Map.put("page", post_context(%{post | title: "About", slug: "about", kind: :page}))
    |> Map.put("pagination", pagination_context(nil, 1))
  end

  defp render(template, context) do
    with {:ok, parsed} <- Solid.parse(template),
         {:ok, output, _context} <- Solid.render(parsed, context) do
      {:ok, IO.iodata_to_binary(output)}
    else
      {:error, errors, output} -> {:error, {errors, IO.iodata_to_binary(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_context(site, theme, pages) do
    variables = Variables.normalize(theme.variables)

    %{
      "site" => %{"name" => site.name, "handle" => site.handle, "tagline" => site.tagline || ""},
      "pages" => Enum.map(pages, &post_context/1),
      "theme_variables" => variables,
      "stylesheet" => (theme.stylesheet || "") <> "\n\n" <> Variables.to_stylesheet(variables)
    }
  end

  defp post_context(post) do
    published_at = post.published_at || post.inserted_at || DateTime.utc_now()

    %{
      "id" => post.id,
      "title" => post.title,
      "slug" => post.slug,
      "excerpt" => post.excerpt || "",
      "tags" => post.tags || [],
      "body" => post.body,
      "body_html" => post.body |> Markdown.to_html() |> Phoenix.HTML.safe_to_string(),
      "kind" => to_string(post.kind),
      "url" => if(post.kind == :page, do: "/#{post.slug}/", else: "/blog/#{post.slug}/"),
      "published_at" => DateTime.to_iso8601(published_at),
      "published_on" => Calendar.strftime(published_at, "%B %-d, %Y"),
      "reading_time" => Publishing.Post.reading_time(post)
    }
  end

  defp pagination_context(%Flop.Meta{} = pagination, _post_count) do
    current_page = pagination.current_page || 1

    %{
      "current_page" => current_page,
      "total_pages" => pagination.total_pages || 0,
      "total_count" => pagination.total_count || 0,
      "page_size" => pagination.page_size || 0,
      "has_previous_page" => pagination.has_previous_page?,
      "has_next_page" => pagination.has_next_page?,
      "previous_url" => if(pagination.has_previous_page?, do: pagination_url(current_page - 1)),
      "next_url" => if(pagination.has_next_page?, do: pagination_url(current_page + 1))
    }
  end

  defp pagination_context(_pagination, post_count) do
    %{
      "current_page" => 1,
      "total_pages" => if(post_count > 0, do: 1, else: 0),
      "total_count" => post_count,
      "page_size" => 20,
      "has_previous_page" => false,
      "has_next_page" => false,
      "previous_url" => nil,
      "next_url" => nil
    }
  end

  defp pagination_url(1), do: "/"
  defp pagination_url(page), do: "/?page=#{page}"
end
