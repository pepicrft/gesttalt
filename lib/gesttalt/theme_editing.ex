defmodule Gesttalt.ThemeEditing do
  @moduledoc "In-process theme drafts created and managed through the Model Context Protocol."

  alias Gesttalt.Plans
  alias Gesttalt.Sites
  alias Gesttalt.Sites.{Site, Theme}
  alias Gesttalt.ThemeEditing.Session
  alias Gesttalt.Themes.Variables

  @theme_fields [
    :name,
    :index_template,
    :article_template,
    :page_template,
    :stylesheet,
    :variables
  ]

  @doc "Creates an isolated draft from the publication's active theme."
  def create(%Site{} = site) do
    with :ok <- Plans.authorize(site, :custom_themes) do
      session_id = random_id()
      theme = Sites.get_theme!(site)

      case DynamicSupervisor.start_child(
             Gesttalt.ThemeEditing.SessionSupervisor,
             {Session, id: session_id, site_id: site.id, theme: theme}
           ) do
        {:ok, _pid} -> fetch(session_id, site)
        {:error, {:already_started, _pid}} -> create(site)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc false
  def fetch(session_id) when is_binary(session_id), do: call(session_id, :fetch)

  @doc "Fetches a draft only when it belongs to the given publication."
  def fetch(session_id, %Site{id: site_id}) when is_binary(session_id),
    do: call(session_id, {:fetch, site_id})

  @doc "Applies a partial theme change and advances the preview revision."
  def update(session_id, %Site{id: site_id}, attrs)
      when is_binary(session_id) and is_map(attrs) do
    attrs = take_theme_fields(attrs)

    if map_size(attrs) == 0,
      do: {:error, :no_theme_changes},
      else: call(session_id, {:update, site_id, attrs})
  end

  @doc "Atomically snapshots, persists, and closes an authorized theme draft."
  def publish(session_id, %Site{} = site) when is_binary(session_id) do
    with :ok <- Plans.authorize(site, :custom_themes),
         {:ok, draft} <- call(session_id, {:begin_publish, site.id}) do
      persist_theme(session_id, site, draft)
    end
  end

  @doc "Closes a draft without modifying the publication's active theme."
  def discard(session_id, %Site{id: site_id}) when is_binary(session_id),
    do: call(session_id, {:discard, site_id})

  @doc false
  def present(session, origin \\ GesttaltWeb.Endpoint.url()) do
    %{
      session_id: session.id,
      preview_url: String.trim_trailing(origin, "/") <> preview_path(session.id),
      revision: session.revision,
      created_at: DateTime.to_iso8601(session.created_at),
      theme: theme_attrs(session.theme),
      variable_contract: Variables.contract()
    }
  end

  @doc false
  def preview_path(session_id), do: "/theme-previews/#{session_id}"

  @doc false
  def topic(session_id), do: "theme-editing:#{session_id}"

  @doc false
  def theme_attrs(%Theme{} = theme) do
    theme
    |> Map.take(@theme_fields)
    |> Map.update!(:variables, &Variables.normalize/1)
  end

  defp call(session_id, message) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{pid, _value}] ->
        try do
          GenServer.call(pid, message)
        catch
          :exit, {:noproc, _call} -> {:error, :not_found}
          :exit, {:normal, _call} -> {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp take_theme_fields(attrs) do
    fields = @theme_fields ++ Enum.map(@theme_fields, &Atom.to_string/1)
    Map.take(attrs, fields)
  end

  defp persist_theme(session_id, site, draft) do
    result =
      try do
        Sites.update_theme(site, theme_attrs(draft))
      rescue
        exception ->
          _result = call(session_id, {:resume_publish, site.id})
          reraise exception, __STACKTRACE__
      catch
        kind, reason ->
          _result = call(session_id, {:resume_publish, site.id})
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    case result do
      {:ok, theme} ->
        _result = call(session_id, {:finish_publish, site.id})
        {:ok, theme}

      {:error, _reason} = error ->
        _result = call(session_id, {:resume_publish, site.id})
        error
    end
  end

  defp random_id, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
