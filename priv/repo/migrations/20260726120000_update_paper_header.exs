defmodule Gesttalt.Repo.Migrations.UpdatePaperHeader do
  use Ecto.Migration

  @index_navigation_before [
                             ~s(          <a href="/">Writing</a>),
                             ~s(          {% for page in pages %}<a href="{{ page.url }}">{{ page.title }}</a>{% endfor %})
                           ]
                           |> Enum.join("\n")

  @index_navigation_after [
                            ~s(          <a href="/">Writing</a>),
                            ~s(          <a href="/photography">Photography</a>),
                            ~s(          {% for page in pages %}<a href="{{ page.url }}">{{ page.title }}</a>{% endfor %})
                          ]
                          |> Enum.join("\n")

  @article_navigation_before ~s(<nav><a href="/">Writing</a>{% for page in pages %}<a href="{{ page.url }}">{{ page.title }}</a>{% endfor %}</nav>)
  @article_navigation_after ~s(<nav><a href="/">Writing</a><a href="/photography">Photography</a>{% for page in pages %}<a href="{{ page.url }}">{{ page.title }}</a>{% endfor %}</nav>)

  @page_navigation_before ~s(<nav><a href="/">Writing</a>{% for item in pages %}<a href="{{ item.url }}">{{ item.title }}</a>{% endfor %}</nav>)
  @page_navigation_after ~s(<nav><a href="/">Writing</a><a href="/photography">Photography</a>{% for item in pages %}<a href="{{ item.url }}">{{ item.title }}</a>{% endfor %}</nav>)

  @header_styles_before ".header-inner { display: flex; align-items: center; justify-content: space-between; gap: 1.5rem; }"
  @header_styles_after ".header-inner { align-items: flex-start; display: flex; flex-direction: column; gap: 1.5rem; }"

  @mobile_styles_before "@media (max-width: 640px) { .header-inner, .post-row { display: flex; flex-direction: column; } .post-row { gap: .35rem; } #site-footer > [data-part=\"inner\"] { flex-wrap: wrap; } }"
  @mobile_styles_after "@media (max-width: 640px) { .post-row { display: flex; flex-direction: column; gap: .35rem; } #site-footer > [data-part=\"inner\"] { flex-wrap: wrap; } }"

  def up do
    replace_fragment(:index_template, @index_navigation_before, @index_navigation_after)
    replace_fragment(:article_template, @article_navigation_before, @article_navigation_after)
    replace_fragment(:page_template, @page_navigation_before, @page_navigation_after)
    replace_fragment(:stylesheet, @header_styles_before, @header_styles_after)
    replace_fragment(:stylesheet, @mobile_styles_before, @mobile_styles_after)
  end

  def down do
    replace_fragment(:index_template, @index_navigation_after, @index_navigation_before)
    replace_fragment(:article_template, @article_navigation_after, @article_navigation_before)
    replace_fragment(:page_template, @page_navigation_after, @page_navigation_before)
    replace_fragment(:stylesheet, @header_styles_after, @header_styles_before)
    replace_fragment(:stylesheet, @mobile_styles_after, @mobile_styles_before)
  end

  defp replace_fragment(column, before, replacement) do
    execute("""
    UPDATE themes
    SET #{column} = replace(#{column}, $before$#{before}$before$, $replacement$#{replacement}$replacement$)
    WHERE name = 'Paper'
      AND position($before$#{before}$before$ in #{column}) > 0
    """)
  end
end
