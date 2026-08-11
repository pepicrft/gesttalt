defmodule Gesttalt.Markdown do
  @moduledoc "Safe rendering for the Markdown source stored with each article."

  @doc "Turns Markdown into escaped HTML suitable for a public article."
  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end

  def to_html(nil), do: Phoenix.HTML.raw("")

  @doc "Turns Markdown into compact plain text for contexts that cannot render HTML."
  def to_text(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_delta!()
    |> Enum.map_join(fn
      %{"insert" => insert} when is_binary(insert) -> insert
      _operation -> ""
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def to_text(nil), do: ""
end
