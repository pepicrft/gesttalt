defmodule Gesttalt.ChangelogTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Changelog

  test "loads repository-authored entries in reverse chronological order" do
    entries = Changelog.list()
    [latest | _rest] = entries

    assert latest.slug == "follow-gesttalt-updates"
    assert latest.published_on == ~D[2026-07-25]
    assert latest.title == "Follow what changes in Gesttalt"
    assert latest.summary =~ "public changelog"

    assert entries ==
             Enum.sort_by(
               entries,
               fn entry -> {Date.to_iso8601(entry.published_on), entry.slug} end,
               :desc
             )
  end

  test "renders safe entry HTML" do
    [entry | _rest] = Changelog.list()
    html = entry |> Changelog.body_html() |> Phoenix.HTML.safe_to_string()

    assert html =~ "<p>Gesttalt now has a public home"
    assert html =~ ~s(<a href="https://www.rssboard.org/rss-specification")
  end
end
