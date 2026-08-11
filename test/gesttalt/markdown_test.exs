defmodule Gesttalt.MarkdownTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Markdown

  test "turns Markdown into compact plain text" do
    markdown =
      "## A heading\n\nBullish on [Once](https://buildonce.dev) and **agent-friendly builds**."

    assert Markdown.to_text(markdown) ==
             "A heading Bullish on Once and agent-friendly builds."
  end
end
