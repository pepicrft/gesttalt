defmodule Gesttalt.Repo.Migrations.AddVariablesToThemes do
  use Ecto.Migration

  @defaults %{
    "colors" => %{
      "text" => "#171411",
      "background" => "#fdfbf7",
      "primary" => "#0062cc",
      "secondary" => "#5b4b8a",
      "accent" => "#b45309",
      "highlight" => "#fff1a8",
      "muted" => "#f7f4ef",
      "surface" => "#f7f4ef",
      "border" => "#e4ddd2",
      "mutedText" => "#5c5751"
    },
    "fonts" => %{
      "body" => ~s(system-ui, -apple-system, "Segoe UI", sans-serif),
      "heading" => ~s(system-ui, -apple-system, "Segoe UI", sans-serif),
      "monospace" => "ui-monospace, monospace"
    },
    "fontSizes" => %{
      "small" => "0.875rem",
      "body" => "1rem",
      "lead" => "1.1rem",
      "heading" => "clamp(1.75rem, 5vw, 2.6rem)"
    },
    "fontWeights" => %{"body" => "400", "heading" => "700", "bold" => "700"},
    "lineHeights" => %{"body" => "1.7", "heading" => "1.15"},
    "space" => %{
      "1" => "0.25rem",
      "2" => "0.5rem",
      "3" => "1rem",
      "4" => "1.5rem",
      "5" => "2.5rem",
      "6" => "4rem"
    },
    "radii" => %{
      "small" => "0.2rem",
      "medium" => "0.5rem",
      "large" => "1rem",
      "round" => "9999px"
    },
    "sizes" => %{"content" => "760px"},
    "shadows" => %{"card" => "0 1px 3px rgb(23 20 17 / 0.12)"}
  }

  def change do
    alter table(:themes) do
      add :variables, :map, null: false, default: @defaults
    end
  end
end
