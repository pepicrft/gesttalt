defmodule Gesttalt.Sites.Domain do
  @moduledoc "A verified host name that resolves to a Gesttalt site."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.Site

  schema "domains" do
    field :hostname, :string
    field :kind, Ecto.Enum, values: [:subdomain, :custom], default: :custom
    field :status, Ecto.Enum, values: [:pending, :active], default: :pending
    field :verification_token, :string
    field :verified_at, :utc_datetime

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [:site_id, :hostname, :kind, :status, :verification_token, :verified_at])
    |> update_change(:hostname, &normalize/1)
    |> validate_required([:site_id, :hostname, :kind, :status, :verification_token])
    |> validate_format(:hostname, ~r/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/)
    |> unique_constraint(:hostname)
  end

  def normalize(hostname) do
    hostname
    |> String.downcase()
    |> String.trim()
    |> String.trim_trailing(".")
  end
end
