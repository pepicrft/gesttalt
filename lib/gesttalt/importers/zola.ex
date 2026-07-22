defmodule Gesttalt.Importers.Zola do
  @moduledoc "Imports the TOML-frontmatter Markdown content used by pepicrft.me and other Zola sites."

  alias Gesttalt.Publishing
  alias Gesttalt.Sites.Site

  def import(%Site{} = site, root) do
    root
    |> content_files()
    |> Enum.reduce(%{created: 0, updated: 0, skipped: 0}, fn file, counts ->
      case parse(file) do
        {:ok, attrs} -> upsert(site, attrs, counts)
        {:error, _reason} -> Map.update!(counts, :skipped, &(&1 + 1))
      end
    end)
  end

  defp content_files(root) do
    patterns = [
      Path.join([root, "content", "blog", "**", "*.md"]),
      Path.join([root, "content", "pages", "**", "*.md"])
    ]

    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&(Path.basename(&1) == "_index.md"))
    |> Enum.uniq()
  end

  defp parse(file) do
    with {:ok, source} <- File.read(file),
         ["", frontmatter, body] <- String.split(source, "+++", parts: 3) do
      metadata = parse_frontmatter(frontmatter)
      kind = if String.contains?(file, "/pages/"), do: :page, else: :post
      slug = metadata["slug"] || file |> Path.basename(".md")
      body = body |> String.trim() |> body_or_description(metadata)

      {:ok,
       %{
         title: metadata["title"],
         slug: slug,
         excerpt: metadata["description"] || metadata["excerpt"],
         body: body,
         kind: kind,
         status: :published,
         published_at: parse_date(metadata["date"])
       }}
    else
      _ -> {:error, :invalid_document}
    end
  end

  defp parse_frontmatter(frontmatter) do
    frontmatter
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, metadata ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> Map.put(metadata, String.trim(key), parse_value(String.trim(value)))
        _ -> metadata
      end
    end)
  end

  defp parse_value("\"" <> _rest = value) do
    case JSON.decode(value) do
      {:ok, decoded} -> decoded
      _ -> String.trim(value, "\"")
    end
  end

  defp parse_value(value), do: value

  defp parse_date(%DateTime{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    value = String.trim(value, "\"")

    case DateTime.from_iso8601(value) do
      {:ok, date, _offset} ->
        DateTime.truncate(date, :second)

      _ ->
        case Date.from_iso8601(value) do
          {:ok, date} -> DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
          _ -> DateTime.utc_now() |> DateTime.truncate(:second)
        end
    end
  end

  defp parse_date(_value), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp body_or_description("", metadata),
    do:
      metadata["description"] || metadata["excerpt"] || "Imported from the original publication."

  defp body_or_description(body, _metadata), do: body

  defp upsert(site, attrs, counts) do
    case Publishing.get_post_by_slug(site, attrs.slug) do
      nil ->
        case Publishing.create_post(site, attrs) do
          {:ok, _post} -> Map.update!(counts, :created, &(&1 + 1))
          {:error, _reason} -> Map.update!(counts, :skipped, &(&1 + 1))
        end

      post ->
        case Publishing.update_post(post, attrs) do
          {:ok, _post} -> Map.update!(counts, :updated, &(&1 + 1))
          {:error, _reason} -> Map.update!(counts, :skipped, &(&1 + 1))
        end
    end
  end
end
