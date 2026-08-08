defmodule Gesttalt.ChangelogTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Changelog

  test "loads repository-authored entries in reverse chronological order" do
    entries = Changelog.list()
    [latest | _rest] = entries

    assert latest.slug == "open-source"
    assert latest.published_on == ~D[2026-08-08]
    assert latest.title == "Gesttalt is now open source"
    assert latest.summary =~ "available to read, adapt, and run"

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
    assert html =~ "<p>Gesttalt is now developed in public"
    assert html =~ ~s(<a href="https://github.com/pepicrft/gesttalt")
  end
end
