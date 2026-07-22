defmodule Gesttalt.Repo.Migrations.AddAgentAuthClaimAttemptExpiry do
  use Ecto.Migration

  def up do
    alter table(:agent_auth_registrations) do
      add :claim_attempt_expires_at, :utc_datetime
    end

    execute("""
    UPDATE agent_auth_registrations
    SET claim_attempt_expires_at = expires_at
    WHERE claim_attempt_expires_at IS NULL
    """)

    alter table(:agent_auth_registrations) do
      modify :claim_attempt_expires_at, :utc_datetime, null: false
    end
  end

  def down do
    alter table(:agent_auth_registrations) do
      remove :claim_attempt_expires_at
    end
  end
end
