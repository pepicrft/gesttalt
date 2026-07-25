defmodule Gesttalt.Repo.Migrations.AddPaginationToPaperTheme do
  use Ecto.Migration

  @body_before "<body>"
  @body_after ~s(<body id="site-home">)

  @index_before "      </section>\n    </main>"

  @index_after [
                 "      </section>",
                 "      {% if pagination.total_pages > 1 %}",
                 "      <nav id=\"posts-pagination\" aria-label=\"Writing pages\">",
                 "        {% if pagination.previous_url %}<a data-part=\"previous\" href=\"{{ pagination.previous_url }}\">Newer posts</a>{% endif %}",
                 "        <span data-part=\"status\">Page {{ pagination.current_page }} of {{ pagination.total_pages }}</span>",
                 "        {% if pagination.next_url %}<a data-part=\"next\" href=\"{{ pagination.next_url }}\">Older posts</a>{% endif %}",
                 "      </nav>",
                 "      {% endif %}",
                 "    </main>"
               ]
               |> Enum.join("\n")

  @stylesheet_before ".prose pre code { padding: 0; }\n#site-footer {"

  @stylesheet_after String.trim_trailing("""
                    .prose pre code { padding: 0; }
                    #site-home {
                      & #posts-pagination {
                        display: grid;
                        grid-template-columns: 1fr auto 1fr;
                        align-items: center;
                        gap: 1rem;
                        padding-block: 1.5rem;

                        & > [data-part="previous"] { grid-column: 1; justify-self: start; }
                        & > [data-part="status"] { grid-column: 2; color: var(--gesttalt-colors-muted-text); }
                        & > [data-part="next"] { grid-column: 3; justify-self: end; }
                      }
                    }
                    #site-footer {
                    """)

  def up do
    replace_fragment(:index_template, @body_before, @body_after)
    replace_fragment(:index_template, @index_before, @index_after)
    replace_fragment(:stylesheet, @stylesheet_before, @stylesheet_after)
  end

  def down do
    replace_fragment(:index_template, @body_after, @body_before)
    replace_fragment(:index_template, @index_after, @index_before)
    replace_fragment(:stylesheet, @stylesheet_after, @stylesheet_before)
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
