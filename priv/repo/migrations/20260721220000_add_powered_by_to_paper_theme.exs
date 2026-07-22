defmodule Gesttalt.Repo.Migrations.AddPoweredByToPaperTheme do
  use Ecto.Migration

  @article_footer_before ~s(<footer class="site-footer"><div class="container"><a href="/">All writing</a></div></footer>)
  @article_footer_after String.trim_trailing("""
                        <footer id="site-footer">
                              <div class="container" data-part="inner">
                                <a href="/">All writing</a>
                                <span data-part="powered-by">Powered by <a href="https://gesttalt.org">Gesttalt</a></span>
                              </div>
                            </footer>
                        """)

  @page_footer_before ~s(<footer class="site-footer"><div class="container">Published with <a href="https://gesttalt.org">gesttalt</a>.</div></footer>)
  @page_footer_after ~s(<footer id="site-footer"><div class="container" data-part="inner"><span data-part="powered-by">Powered by <a href="https://gesttalt.org">Gesttalt</a></span></div></footer>)

  @index_footer_before ~s(<footer class="site-footer"><div class="container">Published with <a href="https://gesttalt.org">gesttalt</a>. <a href="/blog/feed.xml">Really Simple Syndication</a> · <a href="/blog/atom.xml">Atom</a></div></footer>)
  @index_footer_after String.trim_trailing("""
                      <footer id="site-footer">
                            <div class="container" data-part="inner">
                              <span data-part="feeds"><a href="/blog/feed.xml">Really Simple Syndication</a> · <a href="/blog/atom.xml">Atom</a></span>
                              <span data-part="powered-by">Powered by <a href="https://gesttalt.org">Gesttalt</a></span>
                            </div>
                          </footer>
                      """)

  @muted_selector_before ".site-tagline, time, .post-copy p, .site-footer { color: var(--gesttalt-colors-muted-text); }"
  @muted_selector_after ".site-tagline, time, .post-copy p, #site-footer { color: var(--gesttalt-colors-muted-text); }"

  @footer_styles_before ".site-footer { border-top: 1px solid var(--gesttalt-colors-border); padding: 1.5rem 0 2rem; }\n@media (max-width: 640px) { .header-inner, .post-row { display: flex; flex-direction: column; } .post-row { gap: .35rem; } }"
  @footer_styles_after String.trim_trailing("""
                       #site-footer {
                         border-top: 1px solid var(--gesttalt-colors-border);
                         padding: 1.5rem 0 2rem;

                         & > [data-part="inner"] { display: flex; align-items: baseline; gap: 1rem; }
                         & [data-part="powered-by"] { margin-inline-start: auto; white-space: nowrap; }
                       }
                       @media (max-width: 640px) { .header-inner, .post-row { display: flex; flex-direction: column; } .post-row { gap: .35rem; } #site-footer > [data-part="inner"] { flex-wrap: wrap; } }
                       """)

  def up do
    replace_fragment(:article_template, @article_footer_before, @article_footer_after)
    replace_fragment(:page_template, @page_footer_before, @page_footer_after)
    replace_fragment(:index_template, @index_footer_before, @index_footer_after)
    replace_fragment(:stylesheet, @muted_selector_before, @muted_selector_after)
    replace_fragment(:stylesheet, @footer_styles_before, @footer_styles_after)
  end

  def down do
    replace_fragment(:article_template, @article_footer_after, @article_footer_before)
    replace_fragment(:page_template, @page_footer_after, @page_footer_before)
    replace_fragment(:index_template, @index_footer_after, @index_footer_before)
    replace_fragment(:stylesheet, @muted_selector_after, @muted_selector_before)
    replace_fragment(:stylesheet, @footer_styles_after, @footer_styles_before)
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
