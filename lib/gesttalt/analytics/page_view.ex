defmodule Gesttalt.Analytics.PageView do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "analytics_page_views" do
    field :country, :string
    field :path, :string

    belongs_to :site, Gesttalt.Sites.Site

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(page_view, attrs) do
    page_view
    |> cast(attrs, [:site_id, :path, :country])
    |> validate_required([:site_id, :path])
    |> validate_length(:country, is: 2)
    |> validate_format(:country, ~r/^[A-Z]{2}$/)
    |> validate_length(:path, max: 2_048)
    |> validate_format(:path, ~r/^\//)
  end
end
