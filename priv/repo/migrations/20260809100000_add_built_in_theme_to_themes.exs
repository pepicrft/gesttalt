defmodule Gesttalt.Repo.Migrations.AddBuiltInThemeToThemes do
  use Ecto.Migration

  def up do
    alter table(:themes) do
      add :built_in_theme, :string
    end

    execute("UPDATE themes SET built_in_theme = 'paper' WHERE inherited = true")
  end

  def down do
    alter table(:themes) do
      remove :built_in_theme
    end
  end
end
