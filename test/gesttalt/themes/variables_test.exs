defmodule Gesttalt.Themes.VariablesTest do
  use ExUnit.Case, async: true

  alias Gesttalt.Themes.Variables

  test "merges partial standard-variable updates without dropping the scale" do
    assert {:ok, variables} =
             Variables.merge(Variables.defaults(), %{
               "colors" => %{"background" => "#fff4cc", "primary" => "#d73a49"}
             })

    assert variables["colors"]["background"] == "#fff4cc"
    assert variables["colors"]["primary"] == "#d73a49"
    assert variables["colors"]["text"] == "#171411"
    assert variables["fonts"]["body"] =~ "system-ui"
  end

  test "rejects variables outside the published contract" do
    assert {:error, reason} =
             Variables.merge(Variables.defaults(), %{"colors" => %{"surprise" => "hotpink"}})

    assert reason =~ "unknown variable colors.surprise"
  end

  test "rejects values that can escape their custom-property declaration" do
    assert {:error, reason} =
             Variables.merge(Variables.defaults(), %{
               "colors" => %{"primary" => "red; } body { display: none"}
             })

    assert reason =~ "one safe Cascading Style Sheets property value"
  end

  test "falls back to the complete defaults for malformed stored data" do
    malformed = %{"colors" => %{"surprise" => "hotpink"}}

    assert Variables.normalize(malformed) == Variables.defaults()
    assert Variables.to_stylesheet(malformed) =~ "--gesttalt-colors-primary: #0062cc;"
  end

  test "renders stable custom-property names" do
    stylesheet = Variables.to_stylesheet(Variables.defaults())

    assert stylesheet =~ "--gesttalt-colors-primary: #0062cc;"
    assert stylesheet =~ "--gesttalt-font-sizes-body: 1rem;"
    assert stylesheet =~ "--gesttalt-line-heights-heading: 1.15;"
  end

  test "uses one type size for publication text" do
    assert Variables.defaults()["fontSizes"] == %{
             "body" => "1rem",
             "heading" => "1rem",
             "lead" => "1rem",
             "small" => "1rem"
           }
  end
end
