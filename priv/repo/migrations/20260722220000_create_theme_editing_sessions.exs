defmodule Gesttalt.Repo.Migrations.CreateThemeEditingSessions do
  use Ecto.Migration

  def change do
    create table(:theme_editing_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :slot, :integer, null: false
      add :revision, :integer, null: false, default: 0
      add :theme_id, :bigint
      add :name, :string, null: false
      add :index_template, :text, null: false
      add :article_template, :text, null: false
      add :page_template, :text, null: false
      add :stylesheet, :text, null: false
      add :variables, :map, null: false
      add :expires_at, :utc_datetime, null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:theme_editing_sessions, [:site_id, :slot])
    create index(:theme_editing_sessions, [:expires_at])
  end
end
