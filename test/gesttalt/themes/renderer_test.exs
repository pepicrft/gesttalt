defmodule Gesttalt.Themes.RendererTest do
  use Gesttalt.DataCase, async: true

  alias Gesttalt.AccountsFixtures
  alias Gesttalt.Publishing
  alias Gesttalt.Sites
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
        article_template:
          "<title>{{ post.title }}</title><main>{{ post.body_html }}</main><small>{{ post.reading_time }}</small>"
      })

    assert {:ok, html} = Renderer.render_article(site, theme, post, [])
    assert html =~ "<title>Safe themes</title>"
    assert html =~ "<h2>A heading</h2>"
    assert html =~ "<small>1</small>"
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
end
