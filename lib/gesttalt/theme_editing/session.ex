defmodule Gesttalt.ThemeEditing.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  alias Gesttalt.Sites.Theme
  alias Gesttalt.ThemeEditing

  @screenshot_timeout to_timeout(second: 15)
  @max_screenshot_bytes 8_000_000

  @enforce_keys [:id, :site_id, :theme, :created_at, :expires_at]
  defstruct [
    :id,
    :site_id,
    :theme,
    :created_at,
    :expires_at,
    revision: 0,
    status: :editing,
    publisher: nil,
    clients: %{},
    captures: %{}
  ]

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  @impl true
  def init(opts) do
    expires_at = Keyword.fetch!(opts, :expires_at)
    lifetime = max(DateTime.diff(expires_at, now(), :millisecond), 0)
    Process.send_after(self(), :expire, lifetime)

    {:ok,
     %__MODULE__{
       id: Keyword.fetch!(opts, :id),
       site_id: Keyword.fetch!(opts, :site_id),
       theme: Keyword.fetch!(opts, :theme),
       created_at: Keyword.fetch!(opts, :created_at),
       expires_at: expires_at,
       revision: Keyword.fetch!(opts, :revision)
     }}
  end

  @impl true
  def handle_call(:fetch, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:fetch, site_id}, _from, %{site_id: site_id} = state),
    do: {:reply, {:ok, state}, state}

  def handle_call({:fetch, _site_id}, _from, state), do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:connect_preview, site_id, client_id, client_process, attrs},
        _from,
        %{site_id: site_id} = state
      ) do
    state = remove_client(state, client_id, :preview_reconnected)
    now = now()

    client =
      attrs
      |> Map.take([:page, :path, :preview_path, :screenshots_enabled, :viewport])
      |> Map.merge(%{
        client_id: client_id,
        connected_at: now,
        last_seen_at: now,
        monitor: Process.monitor(client_process),
        pid: client_process,
        screenshots_enabled: Map.get(attrs, :screenshots_enabled, false)
      })

    {:reply, {:ok, client}, put_in(state.clients[client_id], client)}
  end

  def handle_call(
        {:connect_preview, _site_id, _client_id, _client_process, _attrs},
        _from,
        state
      ),
      do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:update_preview, site_id, client_id, attrs},
        {client_process, _tag},
        %{site_id: site_id} = state
      ) do
    case Map.fetch(state.clients, client_id) do
      {:ok, %{pid: ^client_process} = client} ->
        client =
          client
          |> Map.merge(
            Map.take(attrs, [:page, :path, :preview_path, :screenshots_enabled, :viewport])
          )
          |> Map.put(:last_seen_at, now())

        {:reply, {:ok, client}, put_in(state.clients[client_id], client)}

      :error ->
        {:reply, {:error, :preview_not_found}, state}

      {:ok, _stale_client} ->
        {:reply, {:error, :preview_not_found}, state}
    end
  end

  def handle_call({:update_preview, _site_id, _client_id, _attrs}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call({:list_previews, site_id}, _from, %{site_id: site_id} = state),
    do: {:reply, {:ok, state.clients}, state}

  def handle_call({:list_previews, _site_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:navigate_preview, site_id, client_id, page},
        _from,
        %{site_id: site_id} = state
      ) do
    case select_client(state, client_id) do
      {:ok, client} ->
        client =
          client
          |> Map.put(:page, page)
          |> Map.put(:path, ThemeEditing.public_page_path(page))
          |> Map.put(:preview_path, ThemeEditing.preview_page_path(state.id, page))
          |> Map.put(:last_seen_at, now())

        send(client.pid, {:theme_preview_navigate, page})
        {:reply, {:ok, client}, put_in(state.clients[client.client_id], client)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:navigate_preview, _site_id, _client_id, _page}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:capture_preview, site_id, client_id},
        from,
        %{site_id: site_id} = state
      ) do
    case select_client(state, client_id) do
      {:ok, %{screenshots_enabled: true} = client} ->
        request_id = random_id()
        timer = Process.send_after(self(), {:screenshot_timeout, request_id}, @screenshot_timeout)
        send(client.pid, {:theme_preview_capture, request_id})

        capture = %{
          client: client,
          from: from,
          timer: timer
        }

        {:noreply, put_in(state.captures[request_id], capture)}

      {:ok, _client} ->
        {:reply, {:error, :screenshot_permission_required}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:capture_preview, _site_id, _client_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:complete_preview_screenshot, client_id, request_id, screenshot},
        {client_process, _tag},
        state
      ) do
    case Map.pop(state.captures, request_id) do
      {%{client: %{client_id: ^client_id, pid: ^client_process}} = capture, captures} ->
        Process.cancel_timer(capture.timer)
        result = validate_screenshot(screenshot, capture.client)
        GenServer.reply(capture.from, result)
        {:reply, :ok, %{state | captures: captures}}

      {_capture, _captures} ->
        {:reply, {:error, :screenshot_request_not_found}, state}
    end
  end

  def handle_call(
        {:fail_preview_screenshot, client_id, request_id, reason},
        {client_process, _tag},
        state
      ) do
    case Map.pop(state.captures, request_id) do
      {%{client: %{client_id: ^client_id, pid: ^client_process}} = capture, captures} ->
        Process.cancel_timer(capture.timer)
        GenServer.reply(capture.from, {:error, normalize_capture_error(reason)})
        {:reply, :ok, %{state | captures: captures}}

      {_capture, _captures} ->
        {:reply, {:error, :screenshot_request_not_found}, state}
    end
  end

  def handle_call(
        {:update, site_id, _attrs},
        _from,
        %{site_id: site_id, status: :publishing} = state
      ),
      do: {:reply, {:error, :publishing}, state}

  def handle_call({:update, site_id, attrs}, _from, %{site_id: site_id} = state) do
    changeset = Theme.changeset(state.theme, attrs)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, _theme} when changeset.changes == %{} ->
        {:reply, {:error, :no_theme_changes}, state}

      {:ok, theme} ->
        state = %{state | theme: theme, revision: state.revision + 1}
        {:reply, {:ok, state}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  def handle_call({:update, _site_id, _attrs}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:broadcast_update, site_id, revision},
        _from,
        %{site_id: site_id} = state
      )
      when revision <= state.revision do
    broadcast(state, {:theme_editing_session_updated, revision})
    {:reply, :ok, state}
  end

  def handle_call({:broadcast_update, _site_id, _revision}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:begin_publish, site_id},
        {publisher, _tag},
        %{
          site_id: site_id,
          status: :editing
        } = state
      ) do
    monitor = Process.monitor(publisher)
    {:reply, {:ok, state.theme}, %{state | status: :publishing, publisher: {publisher, monitor}}}
  end

  def handle_call({:begin_publish, site_id}, _from, %{site_id: site_id} = state),
    do: {:reply, {:error, :publishing}, state}

  def handle_call({:begin_publish, _site_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:resume_publish, site_id},
        _from,
        %{
          site_id: site_id,
          status: :publishing
        } = state
      ) do
    {:reply, :ok, release_publisher(state)}
  end

  def handle_call({:resume_publish, _site_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:finish_publish, site_id},
        _from,
        %{
          site_id: site_id,
          status: :publishing
        } = state
      ) do
    close(state, :ok, :published)
  end

  def handle_call({:finish_publish, _site_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  def handle_call(
        {:finish_discard, site_id},
        _from,
        %{site_id: site_id, status: :publishing} = state
      ) do
    close(state, :ok, :discarded)
  end

  def handle_call({:finish_discard, _site_id}, _from, state),
    do: {:reply, {:error, :not_found}, state}

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, publisher, _reason},
        %{
          status: :publishing,
          publisher: {publisher, monitor}
        } = state
      ) do
    {:noreply, %{state | status: :editing, publisher: nil}}
  end

  def handle_info({:DOWN, monitor, :process, _client_process, _reason}, state) do
    case Enum.find(state.clients, fn {_client_id, client} -> client.monitor == monitor end) do
      {client_id, _client} -> {:noreply, remove_client(state, client_id, :preview_disconnected)}
      nil -> {:noreply, state}
    end
  end

  def handle_info({:screenshot_timeout, request_id}, state) do
    case Map.pop(state.captures, request_id) do
      {nil, _captures} ->
        {:noreply, state}

      {capture, captures} ->
        GenServer.reply(capture.from, {:error, :screenshot_timeout})
        {:noreply, %{state | captures: captures}}
    end
  end

  def handle_info(:expire, %{status: :publishing} = state) do
    Process.send_after(self(), :expire, to_timeout(second: 1))
    {:noreply, state}
  end

  def handle_info(:expire, state) do
    reply_to_captures(state, :session_expired)
    broadcast(state, {:theme_editing_session_closed, :expired})
    {:stop, :normal, state}
  end

  defp close(state, reply, reason) do
    reply_to_captures(state, :session_closed)
    broadcast(state, {:theme_editing_session_closed, reason})
    {:stop, :normal, reply, state}
  end

  defp release_publisher(%{publisher: {_publisher, monitor}} = state) do
    Process.demonitor(monitor, [:flush])
    %{state | status: :editing, publisher: nil}
  end

  defp select_client(%{clients: clients}, nil) when map_size(clients) == 0,
    do: {:error, :no_connected_previews}

  defp select_client(%{clients: clients}, nil) when map_size(clients) == 1,
    do: {:ok, clients |> Map.values() |> hd()}

  defp select_client(%{clients: clients}, nil) when map_size(clients) > 1,
    do: {:error, :preview_client_required}

  defp select_client(%{clients: clients}, client_id) do
    case Map.fetch(clients, client_id) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :preview_not_found}
    end
  end

  defp remove_client(state, client_id, reason) do
    case Map.pop(state.clients, client_id) do
      {nil, _clients} ->
        state

      {client, clients} ->
        Process.demonitor(client.monitor, [:flush])

        captures =
          Enum.reduce(state.captures, state.captures, fn {request_id, capture}, captures ->
            remove_client_capture(
              {request_id, capture},
              captures,
              client_id,
              reason
            )
          end)

        %{state | captures: captures, clients: clients}
    end
  end

  defp remove_client_capture(
         {request_id, %{client: %{client_id: client_id}} = capture},
         captures,
         client_id,
         reason
       ) do
    Process.cancel_timer(capture.timer)
    GenServer.reply(capture.from, {:error, reason})
    Map.delete(captures, request_id)
  end

  defp remove_client_capture(_entry, captures, _client_id, _reason), do: captures

  defp validate_screenshot(
         %{data: data, height: height, mime_type: "image/png", width: width},
         client
       )
       when is_binary(data) and byte_size(data) > 0 and byte_size(data) <= @max_screenshot_bytes and
              is_integer(width) and width > 0 and width <= 16_384 and is_integer(height) and
              height > 0 and height <= 16_384 do
    {:ok,
     %{
       captured_at: now(),
       client_id: client.client_id,
       data: data,
       height: height,
       mime_type: "image/png",
       page: client.page,
       path: client.path,
       preview_path: client.preview_path,
       width: width
     }}
  end

  defp validate_screenshot(_screenshot, _client), do: {:error, :invalid_screenshot}

  defp normalize_capture_error(reason)
       when reason in [:capture_failed, :capture_stream_ended, :screenshot_permission_required],
       do: reason

  defp normalize_capture_error(_reason), do: :capture_failed

  defp reply_to_captures(state, reason) do
    Enum.each(state.captures, fn {_request_id, capture} ->
      Process.cancel_timer(capture.timer)
      GenServer.reply(capture.from, {:error, reason})
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp random_id,
    do: 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp broadcast(state, message),
    do: Phoenix.PubSub.broadcast(Gesttalt.PubSub, ThemeEditing.topic(state.id), message)

  defp via(session_id), do: {:via, Registry, {Gesttalt.ThemeEditing.SessionRegistry, session_id}}
end
