defmodule Gesttalt.Themes.Renderer do
  @moduledoc "Renders tenant-owned Liquid templates with a stable publishing context."

  alias Gesttalt.Markdown
  alias Gesttalt.OpenGraph
  alias Gesttalt.Photography.Photo
  alias Gesttalt.Publishing
  alias Gesttalt.Publishing.Post
  alias Gesttalt.Sites.{Image, Site, Theme, ThemeDefaults}
  alias Gesttalt.Themes.Variables

  def render_index(
        %Site{} = site,
        %Theme{} = theme,
        posts,
        pages,
        pagination \\ nil,
        og \\ nil,
        options \\ []
      ) do
    archive? = Keyword.get(options, :archive, false)
    archive_path = Keyword.get(options, :archive_path, "/blog")

    render(
      theme.index_template,
      base_context(site, theme, pages, og)
      |> Map.put("posts", Enum.map(posts, &post_context(&1, og)))
      |> Map.put("archive_url", archive_path)
      |> Map.put("is_archive", archive?)
      |> Map.put("pagination", pagination_context(pagination, length(posts), archive_path))
    )
  end

  def render_article(%Site{} = site, %Theme{} = theme, %Post{} = post, pages, og \\ nil) do
    render(
      theme.article_template,
      base_context(site, theme, pages, og) |> Map.put("post", post_context(post, og))
    )
  end

  def render_page(%Site{} = site, %Theme{} = theme, %Post{} = page, pages, og \\ nil) do
    render(
      theme.page_template,
      base_context(site, theme, pages, og) |> Map.put("page", post_context(page, og))
    )
  end

  def render_photography(%Site{} = site, %Theme{} = theme, photos, pages, og \\ nil) do
    render(
      theme.photography_template || ThemeDefaults.photography_template(),
      base_context(site, theme, pages, og)
      |> Map.put("photos", Enum.map(photos, &photo_context/1))
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

    photo = %Photo{
      id: 1,
      caption: "A sample photograph for developing a Gesttalt theme.",
      image: %Image{
        id: 1,
        filename: "sample.jpg",
        alt_text: "Soft morning light crossing a quiet room"
      },
      status: :published,
      published_at: now
    }

    base_context(site, %Theme{stylesheet: stylesheet, variables: Variables.defaults()}, [])
    |> Map.put("posts", [post_context(post)])
    |> Map.put("photos", [photo_context(photo)])
    |> Map.put("post", post_context(post))
    |> Map.put("page", post_context(%{post | title: "About", slug: "about", kind: :page}))
    |> Map.put("archive_url", "/blog")
    |> Map.put("is_archive", false)
    |> Map.put("pagination", pagination_context(nil, 1, "/blog"))
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

  defp base_context(site, theme, pages, og \\ nil) do
    variables = Variables.normalize(theme.variables)

    %{
      "site" => %{
        "name" => site.name,
        "handle" => site.handle,
        "tagline" => site.tagline || "",
        "description" => site.description || "",
        "description_html" => site.description |> to_html(),
        "has_description" => has_description?(site.description)
      },
      "pages" => Enum.map(pages, &post_context(&1, og)),
      "theme_variables" => variables,
      "og_image" => home_og_image(site, og),
      "stylesheet" => (theme.stylesheet || "") <> "\n\n" <> Variables.to_stylesheet(variables)
    }
  end

  defp home_og_image(_site, nil), do: ""
  defp home_og_image(site, og), do: OpenGraph.image_url({:home, site}, og)

  defp post_og_image(_post, nil), do: ""

  defp post_og_image(post, og) do
    kind = if post.kind == :page, do: :page, else: :post
    OpenGraph.image_url({kind, post}, og)
  end

  defp post_context(post, og \\ nil) do
    published_at = post.published_at || post.inserted_at || DateTime.utc_now()

    %{
      "id" => post.id,
      "title" => post.title,
      "slug" => post.slug,
      "excerpt" => post.excerpt || "",
      "has_excerpt" => has_excerpt?(post.excerpt),
      "tags" => post.tags || [],
      "body" => post.body,
      "body_html" => post.body |> Markdown.to_html() |> Phoenix.HTML.safe_to_string(),
      "kind" => to_string(post.kind),
      "og_image" => post_og_image(post, og),
      "url" => if(post.kind == :page, do: "/#{post.slug}/", else: "/blog/#{post.slug}/"),
      "published_at" => DateTime.to_iso8601(published_at),
      "published_on" => Calendar.strftime(published_at, "%B %-d, %Y"),
      "reading_time" => Publishing.Post.reading_time(post)
    }
  end

  defp photo_context(photo) do
    published_at = photo.published_at || photo.inserted_at || DateTime.utc_now()

    %{
      "id" => photo.id,
      "caption" => escape(photo.caption),
      "alt_text" => escape(photo.image.alt_text),
      "image_url" => Gesttalt.Sites.image_url(photo.image),
      "published_at" => DateTime.to_iso8601(published_at),
      "published_on" => Calendar.strftime(published_at, "%B %-d, %Y")
    }
  end

  defp escape(value),
    do: value |> then(&(&1 || "")) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp pagination_context(%Flop.Meta{} = pagination, _post_count, archive_path) do
    current_page = pagination.current_page || 1

    %{
      "current_page" => current_page,
      "total_pages" => pagination.total_pages || 0,
      "total_count" => pagination.total_count || 0,
      "page_size" => pagination.page_size || 0,
      "has_previous_page" => pagination.has_previous_page?,
      "has_next_page" => pagination.has_next_page?,
      "previous_url" =>
        if(pagination.has_previous_page?, do: pagination_url(current_page - 1, archive_path)),
      "next_url" =>
        if(pagination.has_next_page?, do: pagination_url(current_page + 1, archive_path))
    }
  end

  defp pagination_context(_pagination, post_count, _archive_path) do
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

  defp pagination_url(1, archive_path), do: archive_path
  defp pagination_url(page, archive_path), do: "#{archive_path}?page=#{page}"

  defp to_html(nil), do: ""
  defp to_html(markdown), do: markdown |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  defp has_description?(description) when is_binary(description),
    do: String.trim(description) != ""

  defp has_description?(_description), do: false

  defp has_excerpt?(excerpt) when is_binary(excerpt), do: String.trim(excerpt) != ""
  defp has_excerpt?(_excerpt), do: false
end
