defmodule Gesttalt.Repo.Migrations.CreateIllegalContentReports do
  use Ecto.Migration

  def change do
    create table(:illegal_content_reports) do
      add :reference, :string, null: false
      add :content_url, :text, null: false
      add :explanation, :text, null: false
      add :reporter_name, :string
      add :reporter_email, :citext
      add :anonymous_sensitive_offence, :boolean, null: false, default: false
      add :good_faith, :boolean, null: false, default: false
      add :status, :string, null: false, default: "received"
      add :decision, :text
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:illegal_content_reports, [:reference])
    create index(:illegal_content_reports, [:status, :inserted_at])
    create index(:illegal_content_reports, [:resolved_at])
  end
end
