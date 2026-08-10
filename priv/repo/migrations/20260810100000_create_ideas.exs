defmodule Gesttalt.Repo.Migrations.CreateIdeas do
  use Ecto.Migration

  def change do
    create table(:ideas) do
      add :title, :string, null: false
      add :notes, :text
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:ideas, [:site_id, :inserted_at])
  end
end
