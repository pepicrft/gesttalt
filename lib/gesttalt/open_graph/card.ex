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
    layout = layout(assigns)

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
            background: #{css(colors["background"])};
            color: #{css(colors["text"])};
            font-family: #{css(fonts["body"])};
            overflow: hidden;
          }
          #{layout_styles(layout, colors, fonts)}
        </style>
      </head>
      <body data-layout="#{layout}">
        #{layout_markup(layout, eyebrow, title, subtitle, meta)}
      </body>
    </html>
    """
  end

  defp layout(%{variant: variant}) when variant in ["inquiry", "studio"], do: variant
  defp layout(_assigns), do: "default"

  defp layout_styles("studio", colors, fonts) do
    """
    body { display: grid; grid-template-rows: 86px 1fr 78px; }
    .studio-top {
      align-items: center;
      border-bottom: 2px solid #{css(colors["border"])};
      display: flex;
      font-family: #{css(fonts["heading"])};
      justify-content: space-between;
      padding-inline: 58px;
    }
    .studio-wordmark { font-size: 28px; font-weight: 700; letter-spacing: -.04em; }
    .studio-meta {
      border: 2px solid #{css(colors["text"])};
      border-radius: 9999px;
      font-size: 19px;
      padding: 10px 17px;
    }
    .studio-main { display: grid; grid-template-columns: minmax(0, 1.7fr) minmax(300px, .7fr); }
    .studio-copy { display: flex; flex-direction: column; justify-content: center; padding: 44px 58px; }
    .studio-title {
      color: #{css(colors["text"])};
      display: -webkit-box;
      font-family: #{css(fonts["heading"])};
      font-size: 74px;
      font-weight: 650;
      letter-spacing: -.06em;
      line-height: 1.06;
      overflow: hidden;
      padding-bottom: .08em;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 3;
    }
    .studio-subtitle {
      color: #{css(colors["mutedText"])};
      display: -webkit-box;
      font-size: 25px;
      line-height: 1.28;
      margin-top: 25px;
      max-width: 620px;
      overflow: hidden;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 2;
    }
    .studio-panels { display: grid; gap: 2px; grid-template-rows: repeat(3, 1fr); padding: 18px 18px 18px 0; }
    .studio-panel:nth-child(1) { background: #dceaff; }
    .studio-panel:nth-child(2) { background: #eee2ff; }
    .studio-panel:nth-child(3) { background: #f5e3d5; }
    .studio-foot {
      align-items: center;
      background: #{css(colors["text"])};
      color: #{css(colors["background"])};
      display: flex;
      font-family: #{css(fonts["heading"])};
      font-size: 20px;
      justify-content: space-between;
      padding-inline: 58px;
    }
    .studio-foot span:last-child { font-weight: 700; }
    """
  end

  defp layout_styles("inquiry", colors, fonts) do
    """
    body { display: grid; grid-template-rows: 78px 1fr 72px; padding-inline: 62px; }
    .inquiry-top {
      align-items: center;
      display: flex;
      font-family: #{css(fonts["heading"])};
      justify-content: space-between;
    }
    .inquiry-wordmark { font-size: 26px; font-weight: 700; letter-spacing: .035em; text-transform: uppercase; }
    .inquiry-meta { color: #{css(colors["mutedText"])}; font-size: 19px; }
    .inquiry-main {
      align-items: center;
      border-bottom: 2px solid #{css(colors["border"])};
      border-top: 2px solid #{css(colors["border"])};
      display: grid;
      gap: 58px;
      grid-template-columns: minmax(0, 1.08fr) minmax(0, .92fr);
      padding-block: 38px;
    }
    .inquiry-title {
      color: #{css(colors["text"])};
      display: -webkit-box;
      font-family: #{css(fonts["heading"])};
      font-size: 72px;
      font-weight: 700;
      letter-spacing: -.055em;
      line-height: 1.06;
      overflow: hidden;
      padding-bottom: .08em;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 3;
    }
    .inquiry-underline {
      background: #{css(colors["text"])};
      display: block;
      height: 7px;
      margin-top: 16px;
      width: 58%;
    }
    .inquiry-context { display: flex; flex-direction: column; gap: 34px; }
    .inquiry-subtitle {
      color: #{css(colors["text"])};
      display: -webkit-box;
      font-family: #{css(fonts["body"])};
      font-size: 31px;
      line-height: 1.2;
      overflow: hidden;
      -webkit-box-orient: vertical;
      -webkit-line-clamp: 3;
    }
    .inquiry-orbit { align-items: center; display: flex; gap: 15px; }
    .inquiry-orbit span { background: #{css(colors["surface"])}; border-radius: 50%; display: block; height: 34px; width: 34px; }
    .inquiry-orbit span:nth-child(2) { background: #{css(colors["accent"])}; height: 56px; width: 56px; }
    .inquiry-orbit span:nth-child(3) { background: #{css(colors["highlight"])}; height: 24px; width: 24px; }
    .inquiry-foot {
      align-items: center;
      display: flex;
      font-family: #{css(fonts["heading"])};
      font-size: 19px;
      justify-content: space-between;
    }
    .inquiry-foot span:last-child { text-decoration: underline; text-underline-offset: 5px; }
    """
  end

  defp layout_styles("default", colors, fonts) do
    """
    body { display: flex; flex-direction: column; justify-content: space-between; padding: 72px 80px; }
    .accent-bar { background: #{css(colors["primary"])}; border-radius: 9999px; height: 10px; width: 96px; }
    .eyebrow { color: #{css(colors["mutedText"])}; font-size: 26px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; }
    .title { color: #{css(colors["text"])}; display: -webkit-box; font-family: #{css(fonts["heading"])}; font-size: 78px; font-weight: 700; line-height: 1.08; overflow: hidden; -webkit-box-orient: vertical; -webkit-line-clamp: 3; }
    .subtitle { color: #{css(colors["mutedText"])}; display: -webkit-box; font-size: 34px; line-height: 1.4; overflow: hidden; -webkit-box-orient: vertical; -webkit-line-clamp: 2; }
    .stack { display: flex; flex-direction: column; gap: 28px; }
    .head { display: flex; flex-direction: column; gap: 24px; }
    .foot { align-items: center; border-top: 2px solid #{css(colors["border"])}; color: #{css(colors["mutedText"])}; display: flex; font-size: 26px; justify-content: space-between; padding-top: 28px; }
    .foot .meta { color: #{css(colors["accent"])}; font-weight: 600; }
    """
  end

  defp layout_markup("studio", eyebrow, title, subtitle, meta) do
    """
    <header class="studio-top">
      <span class="studio-wordmark">#{escape(eyebrow)}</span>
      <span class="studio-meta">#{escape(meta_label(meta))}</span>
    </header>
    <main class="studio-main">
      <div class="studio-copy">
        <div class="studio-title">#{escape(title)}</div>
        #{subtitle_markup("studio-subtitle", subtitle)}
      </div>
      <div class="studio-panels" aria-hidden="true"><span class="studio-panel"></span><span class="studio-panel"></span><span class="studio-panel"></span></div>
    </main>
    <footer class="studio-foot"><span>Independent publishing</span><span>Read ↗</span></footer>
    """
  end

  defp layout_markup("inquiry", eyebrow, title, subtitle, meta) do
    """
    <header class="inquiry-top">
      <span class="inquiry-wordmark">#{escape(eyebrow)}</span>
      <span class="inquiry-meta">#{escape(meta_label(meta))}</span>
    </header>
    <main class="inquiry-main">
      <div class="inquiry-heading"><div class="inquiry-title">#{escape(title)}</div><span class="inquiry-underline"></span></div>
      <div class="inquiry-context">
        #{subtitle_markup("inquiry-subtitle", subtitle)}
        <div class="inquiry-orbit" aria-hidden="true"><span></span><span></span><span></span></div>
      </div>
    </main>
    <footer class="inquiry-foot"><span>Questions, observations, and lasting notes.</span><span>Read more ↗</span></footer>
    """
  end

  defp layout_markup("default", eyebrow, title, subtitle, meta) do
    """
    <div class="head">
      <div class="accent-bar"></div>
      <div class="eyebrow">#{escape(eyebrow)}</div>
    </div>
    <div class="stack">
      <div class="title">#{escape(title)}</div>
      #{subtitle_markup("subtitle", subtitle)}
    </div>
    <div class="foot">
      <span>#{escape(eyebrow)}</span>
      <span class="meta">#{escape(meta)}</span>
    </div>
    """
  end

  defp subtitle_markup(_class, ""), do: ""
  defp subtitle_markup(class, subtitle), do: ~s(<div class="#{class}">#{escape(subtitle)}</div>)

  defp meta_label(""), do: "Latest writing"
  defp meta_label(meta), do: meta

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
