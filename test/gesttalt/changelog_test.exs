defmodule Gesttalt.ChangelogTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Changelog

  test "loads repository-authored entries in reverse chronological order" do
    entries = Changelog.list()
    short_notes = Enum.find(entries, &(&1.slug == "short-notes"))
    conversation_ideas = Enum.find(entries, &(&1.slug == "conversation-ideas"))

    assert short_notes.published_on == ~D[2026-08-10]
    assert short_notes.title == "Publish short notes"
    assert short_notes.summary =~ "brief updates"
    assert conversation_ideas.published_on == ~D[2026-08-10]
    assert conversation_ideas.title == "Conversation ideas"
    assert conversation_ideas.summary =~ "Save private prompts"

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
