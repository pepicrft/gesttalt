defmodule Gesttalt.Sites.Site do
  @moduledoc "A publication owned by one Gesttalt account."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Accounts.User
  alias Gesttalt.Photography.Photo
  alias Gesttalt.Sites.{Domain, Image, Theme}

  @type t :: %__MODULE__{}

  @subscription_statuses [:inactive, :trialing, :active, :past_due, :canceled, :comped]

  schema "sites" do
    field :name, :string
    field :handle, :string
    field :tagline, :string
    field :subscription_status, Ecto.Enum, values: @subscription_statuses, default: :inactive
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :cancel_at_period_end, :boolean, default: false
    field :subscription_ends_at, :utc_datetime

    belongs_to :user, User
    has_many :domains, Domain
    has_many :images, Image
    has_many :photos, Photo
    has_one :theme, Theme

    timestamps(type: :utc_datetime)
  end

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:user_id, :name, :handle, :tagline])
    |> update_change(:handle, &normalize_handle/1)
    |> validate_required([:user_id, :name, :handle])
    |> validate_length(:name, max: 100)
    |> validate_length(:handle, min: 2, max: 40)
    |> validate_format(:handle, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> unique_constraint(:user_id)
    |> unique_constraint(:handle)
  end

  def billing_changeset(site, attrs) do
    site
    |> cast(attrs, [
      :subscription_status,
      :stripe_customer_id,
      :stripe_subscription_id,
      :cancel_at_period_end,
      :subscription_ends_at
    ])
    |> unique_constraint(:stripe_customer_id)
    |> unique_constraint(:stripe_subscription_id)
  end

  defp normalize_handle(handle) do
    handle
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
