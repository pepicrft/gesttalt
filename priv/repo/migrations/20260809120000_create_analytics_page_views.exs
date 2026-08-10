defmodule Gesttalt.Repo.Migrations.CreateAnalyticsPageViews do
  use Ecto.Migration

  def change do
    create table(:analytics_page_views) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :path, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:analytics_page_views, [:site_id, :inserted_at])
  end
end
