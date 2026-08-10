defmodule Gesttalt.Publishing.Idea do
  @moduledoc "A private conversation idea owned by a publication."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.Site

  @type t :: %__MODULE__{}

  schema "ideas" do
    field :title, :string
    field :notes, :string

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(idea, attrs) do
    idea
    |> cast(attrs, [:site_id, :title, :notes])
    |> validate_required([:site_id, :title])
    |> validate_length(:title, max: 160)
  end
end
