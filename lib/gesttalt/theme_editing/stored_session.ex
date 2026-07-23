defmodule Gesttalt.ThemeEditing.StoredSession do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Gesttalt.Repo
  alias Gesttalt.Sites.{Site, Theme}

  @max_sessions_per_site 5
  @primary_key {:id, :string, autogenerate: false}

  schema "theme_editing_sessions" do
    field :article_template, :string
    field :expires_at, :utc_datetime
    field :index_template, :string
    field :name, :string
    field :page_template, :string
    field :revision, :integer, default: 0
    field :slot, :integer
    field :stylesheet, :string
    field :theme_id, :integer
    field :variables, :map

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  def create(session_id, %Site{id: site_id}, %Theme{} = theme, expires_at) do
    delete_expired(site_id)

    Enum.reduce_while(1..@max_sessions_per_site, {:error, :too_many_sessions}, fn slot, error ->
      attrs =
        theme
        |> theme_attrs()
        |> Map.merge(%{
          expires_at: expires_at,
          id: session_id,
          revision: 0,
          site_id: site_id,
          slot: slot,
          theme_id: theme.id
        })

      insert_slot(attrs, error)
    end)
  end

  def get(session_id) do
    now = now()

    __MODULE__
    |> where([session], session.id == ^session_id)
    |> where([session], session.expires_at > ^now)
    |> Repo.one()
  end

  def persist_draft(session) do
    attrs =
      session.theme
      |> theme_attrs()
      |> Map.put(:revision, session.revision)
      |> Map.put(:updated_at, now())

    {count, _result} =
      __MODULE__
      |> where([stored], stored.id == ^session.id)
      |> where([stored], stored.revision < ^session.revision)
      |> Repo.update_all(set: Map.to_list(attrs))

    case count do
      1 -> :ok
      0 -> persisted_or_missing(session.id, session.revision)
    end
  end

  def delete(session_id, site_id) do
    {count, _result} =
      __MODULE__
      |> where([session], session.id == ^session_id and session.site_id == ^site_id)
      |> Repo.delete_all()

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  def delete_in_transaction(session_id, site_id) do
    case Repo.get_by(__MODULE__, id: session_id, site_id: site_id) do
      nil -> Repo.rollback(:not_found)
      stored_session -> Repo.delete!(stored_session)
    end
  end

  def to_session_options(%__MODULE__{} = stored_session) do
    [
      created_at: stored_session.inserted_at,
      expires_at: stored_session.expires_at,
      id: stored_session.id,
      revision: stored_session.revision,
      site_id: stored_session.site_id,
      theme: to_theme(stored_session)
    ]
  end

  defp changeset(stored_session, attrs) do
    stored_session
    |> cast(attrs, [
      :article_template,
      :expires_at,
      :id,
      :index_template,
      :name,
      :page_template,
      :revision,
      :site_id,
      :slot,
      :stylesheet,
      :theme_id,
      :variables
    ])
    |> validate_required([
      :article_template,
      :expires_at,
      :id,
      :index_template,
      :name,
      :page_template,
      :site_id,
      :slot,
      :stylesheet,
      :variables
    ])
    |> unique_constraint(:slot, name: :theme_editing_sessions_site_id_slot_index)
  end

  defp delete_expired(site_id) do
    now = now()

    __MODULE__
    |> where([session], session.site_id == ^site_id and session.expires_at <= ^now)
    |> Repo.delete_all()
  end

  defp persisted_or_missing(session_id, revision) do
    case Repo.get(__MODULE__, session_id) do
      %{revision: stored_revision} when stored_revision >= revision -> :ok
      _stored_session -> {:error, :session_persistence_failed}
    end
  end

  defp insert_slot(attrs, previous_error) do
    case %__MODULE__{} |> changeset(attrs) |> Repo.insert() do
      {:ok, stored_session} ->
        {:halt, {:ok, stored_session}}

      {:error, changeset} ->
        if(slot_taken?(changeset),
          do: {:cont, previous_error},
          else: {:halt, {:error, changeset}}
        )
    end
  end

  defp slot_taken?(changeset), do: Keyword.has_key?(changeset.errors, :slot)

  defp theme_attrs(theme) do
    Map.take(theme, [
      :article_template,
      :index_template,
      :name,
      :page_template,
      :stylesheet,
      :variables
    ])
  end

  defp to_theme(stored_session) do
    struct!(Theme, %{
      article_template: stored_session.article_template,
      id: stored_session.theme_id,
      index_template: stored_session.index_template,
      name: stored_session.name,
      page_template: stored_session.page_template,
      site_id: stored_session.site_id,
      stylesheet: stored_session.stylesheet,
      variables: stored_session.variables
    })
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
