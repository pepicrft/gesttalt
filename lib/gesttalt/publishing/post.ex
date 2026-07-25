defmodule Gesttalt.Publishing.Post do
  @moduledoc "A draft or published article managed by Gesttalt."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.Site

  @type t :: %__MODULE__{}

  @statuses [:draft, :published]

  schema "posts" do
    field :title, :string
    field :slug, :string
    field :excerpt, :string
    field :tags, {:array, :string}, default: []
    field :body, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :kind, Ecto.Enum, values: [:post, :page], default: :post
    field :published_at, :utc_datetime

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    attrs = maybe_put_slug(post, attrs)

    post
    |> cast(attrs, [
      :site_id,
      :title,
      :slug,
      :excerpt,
      :body,
      :tags,
      :kind,
      :status,
      :published_at
    ])
    |> validate_required([:site_id, :title, :slug, :body, :kind, :status])
    |> validate_length(:title, max: 160)
    |> validate_length(:slug, max: 180)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "may contain lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug, name: :posts_site_id_slug_index)
    |> maybe_set_published_at()
  end

  @doc "Builds the state change used to publish an article."
  def publish_changeset(post) do
    change(post, status: :published, published_at: post.published_at || now())
  end

  @doc "Builds the state change used to return an article to drafts."
  def unpublish_changeset(post) do
    change(post, status: :draft, published_at: nil)
  end

  @doc "Returns true when an article is currently public."
  def published?(%__MODULE__{status: :published, published_at: published_at})
      when not is_nil(published_at),
      do: DateTime.compare(published_at, now()) != :gt

  def published?(_post), do: false

  @doc "Returns a conservative reading time in minutes."
  def reading_time(%__MODULE__{body: body}) do
    body
    |> String.split(~r/\s+/, trim: true)
    |> length()
    |> Kernel./(220)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  defp maybe_put_slug(post, attrs) do
    slug = value(attrs, :slug)
    title = value(attrs, :title)

    cond do
      is_binary(slug) and String.trim(slug) != "" -> attrs
      is_nil(post.slug) and is_binary(title) -> put_slug(attrs, slugify(title))
      true -> attrs
    end
  end

  defp put_slug(attrs, slug) do
    key = if Enum.any?(Map.keys(attrs), &is_binary/1), do: "slug", else: :slug
    Map.put(attrs, key, slug)
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp slugify(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
    |> String.downcase()
  end

  defp maybe_set_published_at(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :published_at)} do
      {:published, nil} -> put_change(changeset, :published_at, now())
      _other -> changeset
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
