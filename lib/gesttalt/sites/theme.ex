defmodule Gesttalt.Sites.Theme do
  @moduledoc "A site-specific set of Liquid templates, standard variables, and Cascading Style Sheets."

  use Ecto.Schema
  import Ecto.Changeset

  alias Gesttalt.Sites.Site
  alias Gesttalt.Themes.Variables

  @max_source_bytes 512_000

  schema "themes" do
    field :name, :string
    field :index_template, :string
    field :article_template, :string
    field :built_in_theme, :string
    field :inherited, :boolean, default: false
    field :page_template, :string
    field :photography_template, :string
    field :stylesheet, :string
    field :variables, :map

    belongs_to :site, Site

    timestamps(type: :utc_datetime)
  end

  def changeset(theme, attrs) do
    attrs = normalize_variables(theme, attrs)

    theme
    |> cast(attrs, [
      :site_id,
      :name,
      :built_in_theme,
      :index_template,
      :inherited,
      :article_template,
      :page_template,
      :photography_template,
      :stylesheet,
      :variables
    ])
    |> validate_required([
      :site_id,
      :name,
      :index_template,
      :article_template,
      :page_template,
      :photography_template,
      :stylesheet,
      :variables
    ])
    |> validate_length(:name, max: 120)
    |> validate_source_size(:index_template)
    |> validate_source_size(:article_template)
    |> validate_source_size(:page_template)
    |> validate_source_size(:photography_template)
    |> validate_source_size(:stylesheet)
    |> validate_change(:variables, fn :variables, variables ->
      case Variables.validate(variables) do
        :ok -> []
        {:error, reason} -> [variables: reason]
      end
    end)
    |> unique_constraint(:site_id)
  end

  defp normalize_variables(theme, attrs) do
    key = if Map.has_key?(attrs, :variables), do: :variables, else: "variables"

    case Map.fetch(attrs, key) do
      {:ok, updates} ->
        case Variables.merge(theme.variables, updates) do
          {:ok, variables} -> Map.put(attrs, key, variables)
          {:error, _reason} -> attrs
        end

      :error ->
        attrs
    end
  end

  defp validate_source_size(changeset, field) do
    validate_change(changeset, field, fn ^field, source ->
      if byte_size(source) <= @max_source_bytes,
        do: [],
        else: [{field, "is too large"}]
    end)
  end
end
