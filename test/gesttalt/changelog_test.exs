defmodule Gesttalt.ChangelogTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Changelog

  test "loads repository-authored entries in reverse chronological order" do
    entries = Changelog.list()
    [latest | _rest] = entries

    assert latest.slug == "photography-feeds"
    assert latest.published_on == ~D[2026-07-25]
    assert latest.title == "Publish a photography feed"
    assert latest.summary =~ "chronological photo feed"

    assert entries ==
             Enum.sort_by(
               entries,
               fn entry -> {Date.to_iso8601(entry.published_on), entry.slug} end,
               :desc
             )
  end

  test "returns the pre-rendered entry body as safe HTML" do
    [entry | _rest] = Changelog.list()
    html = entry |> Changelog.body_html() |> Phoenix.HTML.safe_to_string()

    assert entry.body == html
    assert html =~ "<p>Every publication now has a dedicated photography feed"
    assert html =~ ~s(<a href="https://modelcontextprotocol.io/")
  end
end
