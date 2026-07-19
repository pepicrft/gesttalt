defmodule Gesttalt.Repo.Migrations.AddSubscriptionPeriodToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :cancel_at_period_end, :boolean, null: false, default: false
      add :subscription_ends_at, :utc_datetime
    end
  end
end
