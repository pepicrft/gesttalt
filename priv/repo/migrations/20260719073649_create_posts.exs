defmodule Gesttalt.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :excerpt, :text
      add :body, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:slug])
    create index(:posts, [:status, :published_at])
  end
end
