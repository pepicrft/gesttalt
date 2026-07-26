defmodule Gesttalt.Photography.Photo do
  @moduledoc "A photograph prepared for or published to a publication's photography feed."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.{Image, Site}

  schema "photos" do
    field :caption, :string
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft
    field :published_at, :utc_datetime

    belongs_to :site, Site
    belongs_to :image, Image

    timestamps(type: :utc_datetime)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:site_id, :image_id, :caption, :status, :published_at])
    |> validate_required([:site_id, :image_id, :status])
    |> validate_length(:caption, max: 2_200)
    |> put_publication_time()
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:image_id)
    |> unique_constraint(:image_id)
  end

  def published?(%__MODULE__{status: :published}), do: true
  def published?(%__MODULE__{}), do: false

  defp put_publication_time(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :published_at)} do
      {:published, nil} ->
        put_change(changeset, :published_at, DateTime.utc_now() |> DateTime.truncate(:second))

      {:draft, _published_at} ->
        put_change(changeset, :published_at, nil)

      {_status, _published_at} ->
        changeset
    end
  end
end
