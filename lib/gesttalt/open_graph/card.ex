defmodule Gesttalt.OpenGraph.Card do
  @moduledoc """
  Builds the self-contained HTML document rendered into an Open Graph image.

  The card is styled from the publication's theme design variables (see
  `Gesttalt.Themes.Variables`) so the generated image matches the look of the
  site it represents. The document is fully self-contained: all styles are
  inline and it references no external assets, which is required because the
  headless browser renders it from a local file.
  """

  alias Gesttalt.Themes.Variables

  @width 1200
  @height 630

  @doc "The pixel dimensions every card is rendered at."
  @spec dimensions() :: {pos_integer(), pos_integer()}
  def dimensions, do: {@width, @height}

  @doc """
  Renders the card HTML.

  Expects a map with:

    * `:variables` - the raw theme variables map (normalized internally)
    * `:eyebrow` - small label above the title (usually the publication name)
    * `:title` - the primary heading
    * `:subtitle` - supporting line below the title (may be empty)
    * `:meta` - footer metadata line, e.g. publication date (may be empty)
  """
  @spec html(map()) :: String.t()
  def html(%{variables: variables} = assigns) do
    colors = variables |> Variables.normalize() |> Map.fetch!("colors")
    fonts = variables |> Variables.normalize() |> Map.fetch!("fonts")

    eyebrow = Map.get(assigns, :eyebrow, "")
    title = Map.get(assigns, :title, "")
    subtitle = Map.get(assigns, :subtitle, "")
    meta = Map.get(assigns, :meta, "")
    theme_fingerprint = Map.get(assigns, :theme_fingerprint, "")

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <!-- Theme: #{escape(theme_fingerprint)} -->
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: #{@width}px; height: #{@height}px; }
          body {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            padding: 72px 80px;
            background: #{css(colors["background"])};
            color: #{css(colors["text"])};
            font-family: #{css(fonts["body"])};
          }
          .accent-bar {
            width: 96px;
            height: 10px;
            border-radius: 9999px;
            background: #{css(colors["primary"])};
          }
          .eyebrow {
            font-size: 26px;
            font-weight: 600;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: #{css(colors["mutedText"])};
          }
          .title {
            font-family: #{css(fonts["heading"])};
            font-size: 78px;
            line-height: 1.08;
            font-weight: 700;
            color: #{css(colors["text"])};
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
            overflow: hidden;
          }
          .subtitle {
            font-size: 34px;
            line-height: 1.4;
            color: #{css(colors["mutedText"])};
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
          }
          .stack { display: flex; flex-direction: column; gap: 28px; }
          .head { display: flex; flex-direction: column; gap: 24px; }
          .foot {
            display: flex;
            align-items: center;
            justify-content: space-between;
            font-size: 26px;
            color: #{css(colors["mutedText"])};
            border-top: 2px solid #{css(colors["border"])};
            padding-top: 28px;
          }
          .foot .meta { color: #{css(colors["accent"])}; font-weight: 600; }
        </style>
      </head>
      <body>
        <div class="head">
          <div class="accent-bar"></div>
          <div class="eyebrow">#{escape(eyebrow)}</div>
        </div>
        <div class="stack">
          <div class="title">#{escape(title)}</div>
          #{if subtitle == "", do: "", else: ~s(<div class="subtitle">#{escape(subtitle)}</div>)}
        </div>
        <div class="foot">
          <span>#{escape(eyebrow)}</span>
          <span class="meta">#{escape(meta)}</span>
        </div>
      </body>
    </html>
    """
  end

  # Escapes text destined for element content.
  defp escape(value) when is_binary(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp escape(_value), do: ""

  # Guards a design-variable value used inside a CSS declaration. The values are
  # already validated by `Gesttalt.Themes.Variables`, but strip anything that
  # could break out of the declaration as defense in depth.
  defp css(value) when is_binary(value), do: String.replace(value, ["<", ">", "{", "}", ";"], "")
  defp css(_value), do: ""
end
