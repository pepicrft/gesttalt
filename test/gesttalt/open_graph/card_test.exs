defmodule Gesttalt.OpenGraph.CardTest do
  use ExUnit.Case, async: true

  alias Gesttalt.OpenGraph.Card
  alias Gesttalt.Themes.Variables

  test "renders the title, subtitle, eyebrow and meta into the document" do
    html =
      Card.html(%{
        variables: nil,
        eyebrow: "Field Notes",
        title: "A quiet place for lasting words",
        subtitle: "On writing that endures",
        meta: "May 1, 2026 · 4 min read"
      })

    assert html =~ "Field Notes"
    assert html =~ "A quiet place for lasting words"
    assert html =~ "On writing that endures"
    assert html =~ "May 1, 2026 · 4 min read"
  end

  test "uses the theme's colors and fonts" do
    variables =
      Variables.merge(nil, %{
        "colors" => %{"background" => "#101820", "text" => "#f6f6f6"},
        "fonts" => %{"heading" => "Georgia, serif"}
      })
      |> then(fn {:ok, variables} -> variables end)

    html =
      Card.html(%{variables: variables, eyebrow: "", title: "Themed", subtitle: "", meta: ""})

    assert html =~ "#101820"
    assert html =~ "#f6f6f6"
    assert html =~ "Georgia, serif"
  end

  test "escapes markup in text so it cannot break the document" do
    html =
      Card.html(%{
        variables: nil,
        eyebrow: "",
        title: ~s{<script>alert("x")</script>},
        subtitle: "",
        meta: ""
      })

    refute html =~ "<script>alert"
    assert html =~ "&lt;script&gt;"
  end

  test "omits the subtitle element when empty" do
    html =
      Card.html(%{
        variables: nil,
        eyebrow: "Brand",
        title: "Only a title",
        subtitle: "",
        meta: ""
      })

    refute html =~ ~s(class="subtitle")
  end

  test "renders at the 1200x630 Open Graph dimensions" do
    assert Card.dimensions() == {1200, 630}

    html = Card.html(%{variables: nil, eyebrow: "", title: "Sized", subtitle: "", meta: ""})
    assert html =~ "1200px"
    assert html =~ "630px"
  end

  test "includes the theme fingerprint in the rendered document" do
    html = Card.html(%{variables: %{}, theme_fingerprint: "darkroom-v1"})

    assert html =~ "<!-- Theme: darkroom-v1 -->"
  end
end
