defmodule Gesttalt.ChangelogTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Changelog

  test "loads repository-authored entries in reverse chronological order" do
    entries = Changelog.list()
    [latest | _rest] = entries

    assert latest.slug == "conversation-ideas"
    assert latest.published_on == ~D[2026-08-10]
    assert latest.title == "Conversation ideas"
    assert latest.summary =~ "Save private prompts"

    assert entries ==
             Enum.sort_by(
               entries,
               fn entry -> {Date.to_iso8601(entry.published_on), entry.slug} end,
               :desc
             )
  end

  test "returns the pre-rendered entry body as safe HTML" do
    entry = Enum.find(Changelog.list(), &(&1.slug == "open-source"))
    html = entry |> Changelog.body_html() |> Phoenix.HTML.safe_to_string()

    assert entry.body == html
    assert html =~ "<p>Gesttalt is now developed in public"
    assert html =~ ~s(<a href="https://github.com/pepicrft/gesttalt")
  end
end
