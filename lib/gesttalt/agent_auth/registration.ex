defmodule Gesttalt.AgentAuth.Registration do
  use Ecto.Schema

  import Ecto.Changeset

  alias Gesttalt.Accounts.User
  alias Gesttalt.AgentAuth.Event

  schema "agent_auth_registrations" do
    field :public_id, :string
    field :registration_type, Ecto.Enum, values: [:service_auth]
    field :status, Ecto.Enum, values: [:pending, :claimed, :expired, :revoked]
    field :claim_email, :string
    field :claim_token_hash, :binary
    field :claim_attempt_token_hash, :binary
    field :user_code_hash, :binary
    field :expires_at, :utc_datetime
    field :last_polled_at, :utc_datetime
    field :claimed_at, :utc_datetime
    field :registration_ip, :string

    belongs_to :claimed_by_user, User
    has_many :events, Event, foreign_key: :agent_auth_registration_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :public_id,
      :registration_type,
      :status,
      :claim_email,
      :claim_token_hash,
      :claim_attempt_token_hash,
      :user_code_hash,
      :expires_at,
      :registration_ip
    ])
    |> validate_required([
      :public_id,
      :registration_type,
      :status,
      :claim_email,
      :claim_token_hash,
      :claim_attempt_token_hash,
      :user_code_hash,
      :expires_at
    ])
    |> unique_constraint(:public_id)
    |> unique_constraint(:claim_token_hash)
    |> unique_constraint(:claim_attempt_token_hash)
  end

  def claim_changeset(registration, user_id, now) do
    registration
    |> change(status: :claimed, claimed_by_user_id: user_id, claimed_at: now)
    |> foreign_key_constraint(:claimed_by_user_id)
  end

  def poll_changeset(registration, now), do: change(registration, last_polled_at: now)
  def expire_changeset(registration), do: change(registration, status: :expired)
end
