defmodule Gesttalt.AgentAuth.Event do
  use Ecto.Schema

  import Ecto.Changeset

  alias Gesttalt.AgentAuth.Registration

  schema "agent_auth_events" do
    field :name, :string
    field :metadata, :map, default: %{}

    belongs_to :registration, Registration, foreign_key: :agent_auth_registration_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(registration, name, metadata \\ %{}) do
    %__MODULE__{}
    |> cast(
      %{
        agent_auth_registration_id: registration.id,
        name: name,
        metadata: metadata
      },
      [:agent_auth_registration_id, :name, :metadata]
    )
    |> validate_required([:agent_auth_registration_id, :name])
    |> foreign_key_constraint(:agent_auth_registration_id)
  end
end
