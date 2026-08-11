defmodule Gesttalt.Sites.ThemeDefaults do
  @moduledoc "Built-in themes that a publication can inherit until its owner customizes one."

  alias Gesttalt.Sites.Theme
  alias Gesttalt.Themes.Variables

  @files %{
    index_template: "index.liquid",
    article_template: "article.liquid",
    page_template: "page.liquid",
    photography_template: "photography.liquid",
    stylesheet: "theme.css"
  }

  @themes [
    %{
      id: "inquiry",
      name: "Inquiry",
      description: "A warm, rigorous journal pairing bold headlines with literary reading type.",
      template_dir: "inquiry",
      variables: %{
        "colors" => %{
          "accent" => "#d97857",
          "background" => "#f7f6f1",
          "border" => "#cbc7bc",
          "highlight" => "#d7ddca",
          "muted" => "#efede6",
          "mutedText" => "#67655f",
          "primary" => "#171714",
          "secondary" => "#484741",
          "surface" => "#e5ded1",
          "text" => "#171714"
        },
        "fonts" => %{
          "body" => "Georgia, 'Times New Roman', serif",
          "heading" => "Arial, Helvetica, sans-serif"
        },
        "fontWeights" => %{"heading" => "700"},
        "lineHeights" => %{"body" => "1.45", "heading" => "1"},
        "radii" => %{"large" => "1.25rem", "medium" => "0.65rem", "small" => "0.25rem"},
        "shadows" => %{"card" => "none"},
        "sizes" => %{"content" => "1272px"}
      }
    },
    %{
      id: "studio",
      name: "Studio",
      description: "A spacious editorial canvas with bold statements and modular stories.",
      template_dir: "studio",
      variables: %{
        "colors" => %{
          "accent" => "#8d4f2f",
          "background" => "#f7f7f2",
          "border" => "#c9c9c1",
          "highlight" => "#d9e8ff",
          "muted" => "#e9e9e2",
          "mutedText" => "#65655f",
          "primary" => "#11110f",
          "secondary" => "#30302c",
          "surface" => "#edede7",
          "text" => "#11110f"
        },
        "fontWeights" => %{"heading" => "600"},
        "lineHeights" => %{"body" => "1.55", "heading" => "0.98"},
        "radii" => %{"large" => "1.5rem", "medium" => "0.75rem", "small" => "0.3rem"},
        "shadows" => %{"card" => "none"},
        "sizes" => %{"content" => "1200px"}
      }
    },
    %{
      id: "paper",
      name: "Paper",
      description: "A quiet, considered journal for writing and photographs.",
      template_dir: "paper",
      variables: %{}
    },
    %{
      id: "ledger",
      name: "Ledger",
      description: "A typographic, newspaper-inspired publication with crisp rules.",
      template_dir: "paper",
      variables: %{
        "colors" => %{
          "background" => "#f5f1e8",
          "border" => "#302d28",
          "muted" => "#e9e2d6",
          "mutedText" => "#625d55",
          "primary" => "#9e2f22",
          "surface" => "#e9e2d6",
          "text" => "#1f1d1a"
        },
        "fonts" => %{
          "body" => "Georgia, 'Times New Roman', serif",
          "heading" => "Georgia, 'Times New Roman', serif"
        },
        "sizes" => %{"content" => "900px"}
      }
    },
    %{
      id: "darkroom",
      name: "Darkroom",
      description: "A dark, image-first portfolio with minimal visual noise.",
      template_dir: "paper",
      variables: %{
        "colors" => %{
          "background" => "#121211",
          "border" => "#42413d",
          "muted" => "#1d1d1b",
          "mutedText" => "#b9b6ae",
          "primary" => "#f0c77c",
          "surface" => "#1d1d1b",
          "text" => "#f5f2ea"
        },
        "shadows" => %{"card" => "none"},
        "sizes" => %{"content" => "1040px"}
      }
    },
    %{
      id: "field-notes",
      name: "Field Notes",
      description: "A warm, practical notebook for observations, essays, and travel.",
      template_dir: "paper",
      variables: %{
        "colors" => %{
          "background" => "#f4eedf",
          "border" => "#b9ad96",
          "muted" => "#e8deca",
          "mutedText" => "#6a6254",
          "primary" => "#3a5d4c",
          "surface" => "#e8deca",
          "text" => "#292b24"
        },
        "fonts" => %{
          "heading" => "Georgia, 'Times New Roman', serif",
          "monospace" => "'Courier New', monospace"
        },
        "sizes" => %{"content" => "700px"}
      }
    }
  ]

  @theme_styles %{
    "ledger" => """
    .site-header { border-top: 0; padding-block: .75rem; }
    .header-inner { gap: .8rem; }
    .site-title { letter-spacing: -.035em; }
    nav { border-block: 1px solid var(--gesttalt-colors-border); justify-content: space-between; padding-block: .6rem; width: 100%; }
    .post-row { grid-template-columns: 8rem 1fr; }
    #site-photography .photography-entry { border-inline: 0; box-shadow: none; }
    #site-photography .photography-entry-header { border-bottom: 1px solid var(--gesttalt-colors-border); padding-inline: 0; }
    #site-photography .photography-caption { padding-inline: 0; }
    """,
    "darkroom" => """
    .site-header { border-top-width: 2px; }
    .site-title { letter-spacing: .03em; text-transform: uppercase; }
    nav { gap: 1.5rem; text-transform: uppercase; letter-spacing: .08em; }
    .post-row { grid-template-columns: 1fr; gap: .4rem; }
    .post-row time { order: 2; }
    #site-photography .photography-page { padding-top: 1rem; }
    #site-photography .photography-entry { background: transparent; border: 0; box-shadow: none; }
    #site-photography .photography-entry-header { padding-inline: 0; }
    #site-photography .photography-entry-header > .photography-mark { background: var(--gesttalt-colors-primary); border-color: var(--gesttalt-colors-background); }
    #site-photography .photography-caption { color: var(--gesttalt-colors-muted-text); padding-inline: 0; }
    """,
    "field-notes" => """
    .site-header { border-top-width: 8px; }
    .site-title { font-family: var(--gesttalt-fonts-monospace); text-transform: uppercase; }
    nav a { font-family: var(--gesttalt-fonts-monospace); }
    .section-label { font-family: var(--gesttalt-fonts-monospace); text-transform: uppercase; }
    .post-row { grid-template-columns: 1fr; gap: .35rem; }
    .post-row time { font-family: var(--gesttalt-fonts-monospace); }
    #site-photography .photography-entry { border-radius: var(--gesttalt-radii-small); }
    #site-photography .photography-entry-header { font-family: var(--gesttalt-fonts-monospace); }
    """
  }

  def all, do: @themes

  def default_id, do: "inquiry"

  def fetch(id) when is_binary(id) do
    case Enum.find(@themes, &(&1.id == id)) do
      nil -> {:error, :not_found}
      theme -> {:ok, theme}
    end
  end

  def fetch(_id), do: {:error, :not_found}

  def attrs(id \\ default_id()) do
    case fetch(id) do
      {:ok, theme} -> attrs_for(theme)
      {:error, :not_found} -> attrs_for(default_theme())
    end
  end

  def photography_template, do: read!(paper_theme(), "photography.liquid")

  def preview_style(id) when is_binary(id) do
    variables = attrs(id).variables
    colors = variables["colors"]
    fonts = variables["fonts"]

    [
      "--preview-background: #{colors["background"]}",
      "--preview-ink: #{colors["text"]}",
      "--preview-font: #{fonts["heading"]}"
    ]
    |> Enum.join("; ")
  end

  @doc "Returns a built-in theme for a site without using its saved implementation as the source."
  def theme(site_id, id \\ default_id()) when is_integer(site_id) do
    id = if match?({:ok, _theme}, fetch(id)), do: id, else: default_id()

    struct!(
      Theme,
      attrs(id)
      |> Map.put(:built_in_theme, id)
      |> Map.put(:inherited, true)
      |> Map.put(:site_id, site_id)
    )
  end

  defp attrs_for(theme) do
    {:ok, variables} = Variables.merge(Variables.defaults(), theme.variables)

    @files
    |> Enum.reduce(%{name: theme.name, variables: variables}, fn
      {:stylesheet, filename}, attrs ->
        Map.put(
          attrs,
          :stylesheet,
          read!(theme, filename) <> "\n" <> Map.get(@theme_styles, theme.id, "")
        )

      {key, filename}, attrs ->
        Map.put(attrs, key, read!(theme, filename))
    end)
  end

  defp default_theme, do: Enum.find(@themes, &(&1.id == default_id()))

  defp paper_theme, do: Enum.find(@themes, &(&1.id == "paper"))

  defp read!(theme, filename) do
    :gesttalt
    |> Application.app_dir("priv/themes/#{theme.template_dir}/#{filename}")
    |> File.read!()
  end
end
