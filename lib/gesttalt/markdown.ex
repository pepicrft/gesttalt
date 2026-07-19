defmodule Gesttalt.Markdown do
  @moduledoc "Safe rendering for the Markdown source stored with each article."

  @doc "Turns Markdown into escaped HTML suitable for a public article."
  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end

  def to_html(nil), do: Phoenix.HTML.raw("")
end
