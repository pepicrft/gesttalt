defmodule Gesttalt.Sites.ThemeDefaults do
  @moduledoc "The built-in Paper theme, expressed as Liquid and vanilla Cascading Style Sheets."

  alias Gesttalt.Themes.Variables

  @files %{
    index_template: "index.liquid",
    article_template: "article.liquid",
    page_template: "page.liquid",
    photography_template: "photography.liquid",
    stylesheet: "theme.css"
  }

  def attrs do
    Enum.reduce(@files, %{name: "Paper", variables: Variables.defaults()}, fn
      {key, filename}, attrs ->
        Map.put(attrs, key, read!(filename))
    end)
  end

  def photography_template, do: read!("photography.liquid")

  defp read!(filename) do
    :gesttalt
    |> Application.app_dir("priv/themes/paper/#{filename}")
    |> File.read!()
  end
end
