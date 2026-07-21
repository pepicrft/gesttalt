defmodule Gesttalt.Sites.Image do
  @moduledoc "Metadata for an image stored in Gesttalt's media object storage."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.Site

  schema "images" do
    field :filename, :string
    field :storage_key, :string
    field :content_type, :string
    field :byte_size, :integer
    field :alt_text, :string

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:site_id, :filename, :storage_key, :content_type, :byte_size, :alt_text])
    |> validate_required([:site_id, :filename, :storage_key, :content_type, :byte_size])
    |> validate_number(:byte_size, greater_than: 0, less_than_or_equal_to: 10_485_760)
    |> validate_inclusion(:content_type, ~w(image/jpeg image/png image/gif image/webp))
    |> unique_constraint(:storage_key)
  end
end
