defmodule Gesttalt.Changelog.Entry do
  @moduledoc "A published Gesttalt product update."

  @enforce_keys [:body, :published_on, :slug, :summary, :title]
  defstruct [:body, :published_on, :slug, :summary, :title]

  @slug_pattern ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  def build(path, %{summary: summary, title: title}, body)
      when is_binary(summary) and summary != "" and is_binary(title) and title != "" do
    [year, month, day, slug] =
      path
      |> Path.basename(".md")
      |> String.split("-", parts: 4)

    {:ok, published_on} = Date.from_iso8601("#{year}-#{month}-#{day}")
    true = Regex.match?(@slug_pattern, slug)

    %__MODULE__{
      body: String.trim(body),
      published_on: published_on,
      slug: slug,
      summary: summary,
      title: title
    }
  end
end

defmodule Gesttalt.Changelog.MarkdownConverter do
  @moduledoc false

  def convert(_path, body, _attributes, _options) do
    {:ok, html} =
      MDEx.to_html(body, sanitize: MDEx.Document.default_sanitize_options())

    html
  end
end

defmodule Gesttalt.Changelog do
  @moduledoc """
  Provides repository-authored product updates compiled into the application.

  Entry dates and slugs come from filenames in the form `YYYY-MM-DD-slug.md`.
  Titles and summaries live in the metadata map at the top of each entry.
  """

  alias Gesttalt.Changelog.Entry
  alias Gesttalt.Changelog.MarkdownConverter

  use NimblePublisher,
    build: Entry,
    from: Application.app_dir(:gesttalt, "priv/changelog/*.md"),
    as: :entries,
    html_converter: MarkdownConverter

  @entries Enum.sort_by(
             @entries,
             fn entry -> {Date.to_iso8601(entry.published_on), entry.slug} end,
             :desc
           )

  @doc "Returns every changelog entry in reverse chronological order."
  def list, do: @entries

  @doc "Returns the pre-rendered body of a changelog entry."
  def body_html(%Entry{body: body}), do: Phoenix.HTML.raw(body)

  @doc "Returns the publication timestamp used by changelog feeds."
  def published_at(%Entry{published_on: published_on}) do
    {:ok, published_at} = DateTime.new(published_on, ~T[12:00:00], "Etc/UTC")
    published_at
  end
end
