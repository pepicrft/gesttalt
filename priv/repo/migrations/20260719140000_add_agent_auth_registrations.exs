defmodule Gesttalt.Repo.Migrations.AddAgentAuthRegistrations do
  use Ecto.Migration

  def change do
    create table(:agent_auth_registrations) do
      add :public_id, :string, null: false
      add :registration_type, :string, null: false
      add :status, :string, null: false
      add :claim_email, :string, null: false
      add :claim_token_hash, :binary, null: false
      add :claim_attempt_token_hash, :binary, null: false
      add :user_code_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :last_polled_at, :utc_datetime
      add :claimed_at, :utc_datetime
      add :registration_ip, :string
      add :claimed_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_auth_registrations, [:public_id])
    create unique_index(:agent_auth_registrations, [:claim_token_hash])
    create unique_index(:agent_auth_registrations, [:claim_attempt_token_hash])
    create index(:agent_auth_registrations, [:status, :expires_at])
    create index(:agent_auth_registrations, [:registration_ip, :inserted_at])
    create index(:agent_auth_registrations, [:claimed_by_user_id])

    create table(:agent_auth_events) do
      add :name, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :agent_auth_registration_id,
          references(:agent_auth_registrations, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_auth_events, [:agent_auth_registration_id, :inserted_at])
  end
end
