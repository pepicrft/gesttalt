defmodule Gesttalt.Repo.Migrations.AddCountryToAnalyticsPageViews do
  use Ecto.Migration

  def change do
    alter table(:analytics_page_views) do
      add :country, :string, size: 2
    end

    create index(:analytics_page_views, [:site_id, :country, :inserted_at])
  end
end
