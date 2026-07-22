defmodule Gesttalt.ThemeEditing do
  @moduledoc "Durable theme drafts created and managed through the Model Context Protocol."

  alias Gesttalt.Plans
  alias Gesttalt.Publishing
  alias Gesttalt.Repo
  alias Gesttalt.Sites
  alias Gesttalt.Sites.{Site, Theme}
  alias Gesttalt.ThemeEditing.{Session, StoredSession}
  alias Gesttalt.Themes.Variables

  @session_lifetime to_timeout(hour: 4)

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

      expires_at =
        DateTime.utc_now()
        |> DateTime.add(@session_lifetime, :millisecond)
        |> DateTime.truncate(:second)

      create_session(site, theme, session_id, expires_at)
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

    if map_size(attrs) == 0 do
      {:error, :no_theme_changes}
    else
      with {:ok, session} <- call(session_id, {:update, site_id, attrs}),
           :ok <- persist_update(session) do
        _result = call(session_id, {:broadcast_update, site_id, session.revision})
        {:ok, session}
      end
    end
  end

  @doc "Atomically snapshots, persists, and closes an authorized theme draft."
  def publish(session_id, %Site{} = site) when is_binary(session_id) do
    with :ok <- Plans.authorize(site, :custom_themes),
         {:ok, draft} <- call(session_id, {:begin_publish, site.id}) do
      persist_theme(session_id, site, draft)
    end
  end

  @doc "Closes a draft without modifying the publication's active theme."
  def discard(session_id, %Site{id: site_id}) when is_binary(session_id) do
    with {:ok, _draft} <- call(session_id, {:begin_publish, site_id}) do
      case StoredSession.delete(session_id, site_id) do
        :ok ->
          call(session_id, {:finish_discard, site_id})

        {:error, _reason} = error ->
          _result = call(session_id, {:resume_publish, site_id})
          error
      end
    end
  end

  @doc false
  def connect_preview(session_id, %Site{id: site_id}, client_id, client, attrs)
      when is_binary(session_id) and is_binary(client_id) and is_pid(client) and is_map(attrs),
      do: call(session_id, {:connect_preview, site_id, client_id, client, attrs})

  @doc false
  def update_preview(session_id, %Site{id: site_id}, client_id, attrs)
      when is_binary(session_id) and is_binary(client_id) and is_map(attrs),
      do: call(session_id, {:update_preview, site_id, client_id, attrs})

  @doc "Lists the browser previews currently connected to a theme editing session."
  def list_previews(session_id, %Site{id: site_id}) when is_binary(session_id) do
    with {:ok, clients} <- call(session_id, {:list_previews, site_id}),
         do: {:ok, present_previews(clients)}
  end

  @doc "Navigates one connected browser preview to a public publication path."
  def navigate_preview(session_id, %Site{} = site, client_id, path)
      when is_binary(session_id) and (is_binary(client_id) or is_nil(client_id)) and
             is_binary(path) do
    with {:ok, page} <- page_for_path(site, session_id, path),
         {:ok, preview} <- call(session_id, {:navigate_preview, site.id, client_id, page}) do
      {:ok, present_preview(preview)}
    end
  end

  @doc "Requests a screenshot from one connected browser preview."
  def capture_preview(session_id, %Site{id: site_id}, client_id \\ nil)
      when is_binary(session_id) and (is_binary(client_id) or is_nil(client_id)),
      do: call(session_id, {:capture_preview, site_id, client_id}, to_timeout(second: 20))

  @doc false
  def complete_preview_screenshot(session_id, client_id, request_id, screenshot)
      when is_binary(session_id) and is_binary(client_id) and is_binary(request_id) and
             is_map(screenshot),
      do: call(session_id, {:complete_preview_screenshot, client_id, request_id, screenshot})

  @doc false
  def fail_preview_screenshot(session_id, client_id, request_id, reason)
      when is_binary(session_id) and is_binary(client_id) and is_binary(request_id),
      do: call(session_id, {:fail_preview_screenshot, client_id, request_id, reason})

  @doc false
  def present(session, origin \\ GesttaltWeb.Endpoint.url()) do
    %{
      session_id: session.id,
      preview_url: String.trim_trailing(origin, "/") <> preview_path(session.id),
      revision: session.revision,
      created_at: DateTime.to_iso8601(session.created_at),
      connected_previews: present_previews(session.clients),
      theme: theme_attrs(session.theme),
      variable_contract: Variables.contract()
    }
  end

  @doc false
  def preview_path(session_id), do: "/theme-previews/#{session_id}"

  @doc false
  def preview_page_path(session_id, %{"kind" => "home"}), do: preview_path(session_id)

  def preview_page_path(session_id, page), do: preview_path(session_id) <> public_page_path(page)

  @doc false
  def public_page_path(%{"kind" => "home"}), do: "/"

  def public_page_path(%{"kind" => "article", "slug" => slug}),
    do: "/blog/#{URI.encode(slug)}"

  def public_page_path(%{"kind" => "page", "slug" => slug}), do: "/#{URI.encode(slug)}"

  @doc false
  def page_for_path(%Site{} = site, session_id, path) do
    with {:ok, path} <- public_path(session_id, path) do
      case path |> String.trim("/") |> String.split("/", trim: true) do
        [] ->
          {:ok, %{"kind" => "home", "title" => site.name}}

        ["blog", slug] ->
          page_for_slug(Publishing.list_published_posts(site), "article", URI.decode(slug))

        [slug] ->
          page_for_slug(Publishing.list_published_pages(site), "page", URI.decode(slug))

        _segments ->
          {:error, :preview_page_not_found}
      end
    end
  end

  @doc false
  def topic(session_id), do: "theme-editing:#{session_id}"

  @doc false
  def theme_attrs(%Theme{} = theme) do
    theme
    |> Map.take(@theme_fields)
    |> Map.update!(:variables, &Variables.normalize/1)
  end

  defp call(session_id, message, timeout \\ 5_000) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{pid, _value}] ->
        try do
          GenServer.call(pid, message, timeout)
        catch
          :exit, {:noproc, _call} -> {:error, :not_found}
          :exit, {:normal, _call} -> {:error, :not_found}
          :exit, {:shutdown, _call} -> {:error, :not_found}
          :exit, {{:shutdown, _reason}, _call} -> {:error, :not_found}
          :exit, {:timeout, _call} -> {:error, :preview_timeout}
        end

      [] ->
        with {:ok, _pid} <- restore_session(session_id),
             do: call(session_id, message, timeout)
    end
  end

  defp take_theme_fields(attrs) do
    fields = @theme_fields ++ Enum.map(@theme_fields, &Atom.to_string/1)
    Map.take(attrs, fields)
  end

  defp page_for_slug(posts, kind, slug) do
    case Enum.find(posts, &(&1.slug == slug)) do
      nil -> {:error, :preview_page_not_found}
      post -> {:ok, %{"kind" => kind, "slug" => post.slug, "title" => post.title}}
    end
  end

  defp public_path(session_id, address) do
    path = URI.parse(address).path || ""
    prefix = preview_path(session_id)

    cond do
      path == "" -> {:error, :preview_page_not_found}
      path == prefix -> {:ok, "/"}
      String.starts_with?(path, prefix <> "/") -> {:ok, String.replace_prefix(path, prefix, "")}
      String.starts_with?(path, "/theme-previews/") -> {:error, :preview_page_not_found}
      String.starts_with?(path, "/") -> {:ok, path}
      true -> {:ok, "/" <> path}
    end
  end

  defp present_previews(clients) do
    clients
    |> Map.values()
    |> Enum.map(&present_preview/1)
    |> Enum.sort_by(& &1.connected_at)
  end

  defp present_preview(preview) do
    %{
      client_id: preview.client_id,
      connected_at: DateTime.to_iso8601(preview.connected_at),
      last_seen_at: DateTime.to_iso8601(preview.last_seen_at),
      page: preview.page,
      path: preview.path,
      preview_path: preview.preview_path,
      screenshots_enabled: preview.screenshots_enabled,
      viewport: preview.viewport
    }
  end

  defp persist_theme(session_id, site, draft) do
    result =
      try do
        Repo.transaction(fn ->
          case Sites.update_theme(site, theme_attrs(draft)) do
            {:ok, theme} ->
              StoredSession.delete_in_transaction(session_id, site.id)
              theme

            {:error, changeset} ->
              Repo.rollback({:changeset, changeset})
          end
        end)
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

      {:error, {:changeset, changeset}} ->
        _result = call(session_id, {:resume_publish, site.id})
        {:error, changeset}

      {:error, reason} ->
        _result = call(session_id, {:resume_publish, site.id})
        {:error, reason}
    end
  end

  defp persist_update(session) do
    case StoredSession.persist_draft(session) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        stop_session(session.id)
        error
    end
  end

  defp restore_session(session_id) do
    case StoredSession.get(session_id) do
      nil -> {:error, :not_found}
      stored_session -> start_session(stored_session)
    end
  end

  defp start_session(stored_session) do
    case DynamicSupervisor.start_child(
           Gesttalt.ThemeEditing.SessionSupervisor,
           {Session, StoredSession.to_session_options(stored_session)}
         ) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      result -> result
    end
  end

  defp stop_session(session_id) do
    case Registry.lookup(Gesttalt.ThemeEditing.SessionRegistry, session_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(Gesttalt.ThemeEditing.SessionSupervisor, pid)

      [] ->
        :ok
    end
  end

  defp create_session(site, theme, session_id, expires_at) do
    with {:ok, stored_session} <- StoredSession.create(session_id, site, theme, expires_at) do
      start_created_session(stored_session, site)
    end
  end

  defp start_created_session(stored_session, site) do
    case start_session(stored_session) do
      {:ok, _pid} -> fetch(stored_session.id, site)
      {:error, reason} -> clean_up_failed_start(stored_session, reason)
    end
  end

  defp clean_up_failed_start(stored_session, reason) do
    _result = StoredSession.delete(stored_session.id, stored_session.site_id)
    {:error, reason}
  end

  defp random_id, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
