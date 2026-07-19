defmodule Mix.Tasks.Gesttalt.ImportZola do
  @moduledoc false

  use Mix.Task

  alias Gesttalt.{Accounts, Importers, Sites}

  @shortdoc "Imports posts and pages from a Zola content directory"

  @impl true
  def run(args) do
    {opts, paths, _invalid} = OptionParser.parse(args, strict: [email: :string])
    [root] = paths
    email = opts[:email] || Mix.raise("--email is required")
    Mix.Task.run("app.start")

    user =
      Accounts.get_user_by_email(email) ||
        Mix.raise("No Gesttalt account exists for #{email}")

    {:ok, site} = Sites.ensure_site_for_user(user)
    counts = Importers.Zola.import(site, Path.expand(root))

    Mix.shell().info(
      "Imported #{counts.created}, updated #{counts.updated}, skipped #{counts.skipped}"
    )
  end
end
