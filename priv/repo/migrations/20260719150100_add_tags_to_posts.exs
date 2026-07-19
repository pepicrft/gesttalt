defmodule Gesttalt.Repo.Migrations.AddTagsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :tags, {:array, :string}, null: false, default: []
    end
  end
end
