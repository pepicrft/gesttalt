defmodule Gesttalt.Changelog do
  @moduledoc """
  Loads repository-authored product updates from the application private directory.

  Entry dates and slugs come from filenames in the form `YYYY-MM-DD-slug.md`.
  Titles and summaries live in the small front matter block at the top of each entry.
  """

  alias Gesttalt.Changelog.Entry
  alias Gesttalt.Markdown

  @entry_filename ~r/^(?<date>\d{4}-\d{2}-\d{2})-(?<slug>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$/

  defmodule Entry do
    @moduledoc "A published Gesttalt product update."

    @enforce_keys [:body, :published_on, :slug, :summary, :title]
    defstruct [:body, :published_on, :slug, :summary, :title]
  end

  @doc "Returns every changelog entry in reverse chronological order."
  def list do
    :gesttalt
    |> Application.app_dir("priv/changelog/*.md")
    |> Path.wildcard()
    |> Enum.map(&load!/1)
    |> Enum.sort_by(
      fn entry -> {Date.to_iso8601(entry.published_on), entry.slug} end,
      :desc
    )
  end

  @doc "Renders an entry body as sanitized HTML."
  def body_html(%Entry{body: body}), do: Markdown.to_html(body)

  @doc "Returns the publication timestamp used by changelog feeds."
  def published_at(%Entry{published_on: published_on}) do
    DateTime.new!(published_on, ~T[12:00:00], "Etc/UTC")
  end

  defp load!(path) do
    filename = Path.basename(path)
    captures = filename_captures!(filename)
    {front_matter, body} = path |> File.read!() |> split_document!(filename)
    metadata = parse_front_matter!(front_matter, filename)

    %Entry{
      body: String.trim(body),
      published_on: Date.from_iso8601!(captures["date"]),
      slug: captures["slug"],
      summary: Map.fetch!(metadata, "summary"),
      title: Map.fetch!(metadata, "title")
    }
  end

  defp filename_captures!(filename) do
    Regex.named_captures(@entry_filename, filename) ||
      raise ArgumentError,
            "invalid changelog filename #{inspect(filename)}; expected YYYY-MM-DD-slug.md"
  end

  defp split_document!("+++\n" <> rest, filename) do
    case String.split(rest, "\n+++\n", parts: 2) do
      [front_matter, body] -> {front_matter, body}
      _parts -> raise ArgumentError, "missing closing front matter marker in #{filename}"
    end
  end

  defp split_document!(_source, filename),
    do: raise(ArgumentError, "missing front matter in #{filename}")

  defp parse_front_matter!(front_matter, filename) do
    metadata =
      front_matter
      |> String.split("\n", trim: true)
      |> Map.new(&parse_front_matter_line!(&1, filename))

    for field <- ["title", "summary"] do
      if metadata[field] in [nil, ""] do
        raise ArgumentError, "missing #{field} in #{filename}"
      end
    end

    metadata
  end

  defp parse_front_matter_line!(line, filename) do
    with [key, encoded_value] <- String.split(line, "=", parts: 2),
         key when key in ["title", "summary"] <- String.trim(key),
         {:ok, value} when is_binary(value) <- JSON.decode(String.trim(encoded_value)) do
      {key, value}
    else
      _invalid ->
        raise ArgumentError,
              "invalid changelog front matter line #{inspect(line)} in #{filename}"
    end
  end
end
