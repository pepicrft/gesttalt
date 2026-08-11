defmodule Gesttalt.Themes.RendererTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Publishing
  alias Gesttalt.Sites
  alias Gesttalt.Sites.ThemeDefaults
  alias Gesttalt.Themes.Renderer

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, site} = Sites.ensure_site_for_user(user)
    %{site: site}
  end

  test "renders the stable Liquid article context with sanitized Markdown", %{site: site} do
    {:ok, post} =
      Publishing.create_post(site, %{
        title: "Safe themes",
        body: "## A heading\n\n<script>alert('no')</script>",
        kind: :post,
        status: :published
      })

    {:ok, theme} =
      Sites.update_theme(site, %{
        article_template: "<title>{{ post.title }}</title><main>{{ post.body_html }}</main>"
      })

    assert {:ok, html} = Renderer.render_article(site, theme, post, [])
    assert html =~ "<title>Safe themes</title>"
    assert html =~ "<h2>A heading</h2>"
    refute html =~ "min read"
    refute html =~ "<script>"
  end

  test "makes a sanitized publication description available to Liquid themes", %{site: site} do
    {:ok, site} =
      Sites.update_site(site, %{description: "## Hello\n\n<script>alert('no')</script>"})

    {:ok, theme} =
      Sites.update_theme(site, %{index_template: "<main>{{ site.description_html }}</main>"})

    assert {:ok, html} = Renderer.render_index(site, theme, [], [])
    assert html =~ "<h2>Hello</h2>"
    refute html =~ "<script>"
  end

  test "returns an error for invalid Liquid instead of crashing the request", %{site: site} do
    assert {:error, _reason} = Renderer.render_string("{% if site.name %}", %{"site" => site})
  end

  test "makes standard variables available to both the stylesheet and Liquid", %{site: site} do
    {:ok, theme} =
      Sites.update_theme(site, %{
        index_template:
          "<style>{{ stylesheet }}</style><output>{{ theme_variables.colors.primary }}</output>",
        variables: %{"colors" => %{"primary" => "#d73a49"}}
      })

    assert {:ok, html} = Renderer.render_index(site, theme, [], [])
    assert html =~ "--gesttalt-colors-primary: #d73a49;"
    assert html =~ "<output>#d73a49</output>"
  end

  test "renders safe defaults when stored variables are malformed", %{site: site} do
    theme = %{Sites.get_theme!(site) | variables: %{"colors" => %{"surprise" => "hotpink"}}}

    assert {:ok, html} = Renderer.render_index(site, theme, [], [])
    assert html =~ "--gesttalt-colors-primary: #0062cc;"
    refute html =~ "hotpink"
  end

  test "makes archive pagination available to Liquid themes", %{site: site} do
    {:ok, theme} =
      Sites.update_theme(site, %{
        index_template:
          "<p>{{ pagination.current_page }} of {{ pagination.total_pages }}</p><a href=\"{{ pagination.previous_url }}\">Previous</a><a href=\"{{ pagination.next_url }}\">Next</a>"
      })

    pagination = %Flop.Meta{
      current_page: 2,
      page_size: 20,
      total_count: 41,
      total_pages: 3,
      has_previous_page?: true,
      has_next_page?: true
    }

    assert {:ok, html} =
             Renderer.render_index(site, theme, [], [], pagination, nil,
               archive: true,
               archive_path: "/blog"
             )

    assert html =~ "<p>2 of 3</p>"
    assert html =~ ~s(href="/blog")
    assert html =~ ~s(href="/blog?page=3")
  end

  test "the built-in theme links every footer to Gesttalt", %{site: site} do
    {:ok, post} =
      Publishing.create_post(site, %{
        title: "An article",
        body: "Article body",
        kind: :post,
        status: :published
      })

    {:ok, page} =
      Publishing.create_post(site, %{
        title: "A page",
        body: "Page body",
        kind: :page,
        status: :published
      })

    theme = Sites.get_theme!(site)
    assert {:ok, index_html} = Renderer.render_index(site, theme, [post], [page])
    assert {:ok, article_html} = Renderer.render_article(site, theme, post, [page])
    assert {:ok, page_html} = Renderer.render_page(site, theme, page, [page])
    assert {:ok, photography_html} = Renderer.render_photography(site, theme, [], [page])

    for html <- [index_html, article_html, page_html, photography_html] do
      assert html =~ ~s(Powered by <a href="https://gesttalt.org">Gesttalt</a>)
    end
  end

  test "the default built-in theme has stable editorial structure", %{site: site} do
    theme = Sites.get_theme!(site)

    assert theme.stylesheet =~ "#inquiry-header"
    assert theme.index_template =~ ~s(id="inquiry-introduction")
    assert theme.index_template =~ ~s(id="inquiry-stories")

    assert {:ok, html} = Renderer.render_index(site, theme, [], [])
    assert html =~ ~s(<a href="/blog">Writing</a>)
    assert html =~ ~s(<a href="/photography">Photography</a>)
  end

  test "renders every route for the new editorial themes", %{site: site} do
    {:ok, post} =
      Publishing.create_post(site, %{
        title: "A lasting question",
        excerpt: "An introduction to the work.",
        body: "## Begin here\n\nFollow the evidence.",
        kind: :post,
        status: :published
      })

    {:ok, page} =
      Publishing.create_post(site, %{
        title: "About",
        body: "About this publication.",
        kind: :page,
        status: :published
      })

    for theme_id <- ["inquiry", "studio"] do
      theme = ThemeDefaults.theme(site.id, theme_id)

      assert {:ok, index} = Renderer.render_index(site, theme, [post], [page])
      assert {:ok, article} = Renderer.render_article(site, theme, post, [page])
      assert {:ok, standalone_page} = Renderer.render_page(site, theme, page, [page])
      assert {:ok, photography} = Renderer.render_photography(site, theme, [], [page])

      for html <- [index, article, standalone_page, photography] do
        assert html =~ "Powered by"
        assert html =~ "Gesttalt"
      end
    end
  end
end
