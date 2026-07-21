defmodule Gesttalt.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :gesttalt

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def migrate_and_seed do
    migrate()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed()
          migrate_legacy_media()
        end)
    end
  end

  @doc """
  Puts a site on the complimentary Publisher plan.

      bin/gesttalt eval 'Gesttalt.Release.comp_site("pepicrft")'
  """
  def comp_site(handle), do: with_repo(fn -> Gesttalt.Sites.comp_site(handle) end)

  @doc "Takes a site off the complimentary Publisher plan."
  def uncomp_site(handle), do: with_repo(fn -> Gesttalt.Sites.uncomp_site(handle) end)

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp seed do
    seed_script = Application.app_dir(:gesttalt, "priv/repo/seeds.exs")
    Code.eval_file(seed_script)
  end

  defp migrate_legacy_media do
    {:ok, _applications} = Application.ensure_all_started(:req)
    result = Gesttalt.Sites.migrate_legacy_images()

    if result.failed == [] do
      result
    else
      raise "legacy media migration failed: #{inspect(result.failed)}"
    end
  end

  defp with_repo(fun) do
    load_app()

    {:ok, result, _started} = Ecto.Migrator.with_repo(Gesttalt.Repo, fn _repo -> fun.() end)
    result
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
