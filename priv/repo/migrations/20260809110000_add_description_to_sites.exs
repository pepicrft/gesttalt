defmodule Gesttalt.Repo.Migrations.AddDescriptionToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :description, :text
    end
  end
end
