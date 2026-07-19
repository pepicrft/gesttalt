defmodule Mix.Tasks.Gesttalt.ImportWebsite do
  @moduledoc "Imports a Zola website into a Gesttalt publication."
  @shortdoc "Imports a Zola website into a Gesttalt publication"

  use Mix.Task

  alias Gesttalt.Accounts
  alias Gesttalt.Publishing
  alias Gesttalt.Repo
  alias Gesttalt.Sites

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, switches: [source: :string, email: :string])

    source = opts[:source] || Path.expand("~/src/github.com/pepicrft/website")
    email = opts[:email] || System.get_env("GESTTALT_SEED_EMAIL", "demo@gesttalt.local")
    Mix.Task.run("app.start")

    user = Accounts.get_user_by_email(email) || Mix.raise("No user found for #{email}")
    {:ok, site} = Sites.ensure_site_for_user(user)

    source
    |> Path.join("content/blog/*.md")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "_index.md"))
    |> Enum.each(&import_post(&1, site))
  end

  defp import_post(path, site) do
    {front_matter, body} = path |> File.read!() |> split_document()
    {body, image_count} = import_images(body, path, site)

    attrs = %{
      title: field(front_matter, "title", Path.basename(path, ".md")),
      slug: field(front_matter, "slug", Path.basename(path, ".md")),
      excerpt: field(front_matter, "description", ""),
      tags: tags(front_matter),
      body: body,
      kind: :post,
      status: :published,
      published_at: date(front_matter)
    }

    case Repo.get_by(Gesttalt.Publishing.Post, site_id: site.id, slug: attrs.slug) do
      nil ->
        {:ok, _post} = Publishing.create_post(site, attrs)
        Mix.shell().info("Imported #{attrs.slug} (#{image_count} images)")

      _post ->
        Mix.shell().info("Skipped #{attrs.slug} (already exists)")
    end
  end

  defp split_document("+++\n" <> rest) do
    [front_matter, body] = String.split(rest, "\n+++\n", parts: 2)
    {front_matter, body}
  end

  defp split_document(content), do: {"", content}

  defp import_images(body, post_path, site) do
    rewritten =
      Regex.replace(
        ~r/!\[([^\]]*)\]\(([^)]+)\)/,
        body,
        &import_image(&1, &2, &3, post_path, site)
      )

    {rewritten,
     Regex.scan(~r/!\[[^\]]*\]\(([^)]+)\)/, body)
     |> length()}
  end

  defp import_image(full, alt, reference, post_path, site) do
    source_path =
      if String.starts_with?(reference, "/"),
        do: Path.join(Path.join(Path.dirname(post_path), "../../static"), reference),
        else: Path.expand(reference, Path.dirname(post_path))

    if File.exists?(source_path) do
      upload = %Plug.Upload{
        path: source_path,
        filename: Path.basename(source_path),
        content_type: MIME.from_path(source_path)
      }

      case Sites.store_image(site, upload, alt) do
        {:ok, image} -> "![#{alt}](#{Sites.image_url(image)})"
        _ -> full
      end
    else
      full
    end
  end

  defp field(front_matter, name, default) do
    case Regex.run(~r/^#{name}\s*=\s*[\"'](.*?)[\"']\s*$/m, front_matter, capture: :all_but_first) do
      [value] -> value
      _ -> default
    end
  end

  defp tags(front_matter) do
    case Regex.run(~r/^tags\s*=\s*\[(.*?)\]\s*$/m, front_matter, capture: :all_but_first) do
      [values] ->
        Regex.scan(~r/[\"']([^\"']+)[\"']/, values, capture: :all_but_first) |> List.flatten()

      _ ->
        []
    end
  end

  defp date(front_matter) do
    case Regex.run(~r/^date\s*=\s*(\d{4}-\d{2}-\d{2})/m, front_matter, capture: :all_but_first) do
      [value] ->
        Date.from_iso8601!(value)
        |> NaiveDateTime.new!(~T[12:00:00])
        |> DateTime.from_naive!("Etc/UTC")

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end
end
