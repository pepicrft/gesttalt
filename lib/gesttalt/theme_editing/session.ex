defmodule Gesttalt.ThemeEditing.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  alias Gesttalt.Sites.Theme
  alias Gesttalt.ThemeEditing

  @session_lifetime to_timeout(hour: 4)
  @max_sessions_per_site 5

  @enforce_keys [:id, :site_id, :theme, :created_at]
  defstruct [:id, :site_id, :theme, :created_at, revision: 0, status: :editing, publisher: nil]

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  @impl true
  def init(opts) do
    site_id = Keyword.fetch!(opts, :site_id)

    with {:ok, _slot} <- claim_slot(site_id) do
      Process.send_after(self(), :expire, @session_lifetime)

      {:ok,
       %__MODULE__{
         id: Keyword.fetch!(opts, :id),
         site_id: site_id,
         theme: Keyword.fetch!(opts, :theme),
         created_at: DateTime.utc_now() |> DateTime.truncate(:second)
       }}
    end
  end

  @impl true
  def handle_call(:fetch, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:fetch, site_id}, _from, %{site_id: site_id} = state),
    do: {:reply, {:ok, state}, state}

  def handle_call({:fetch, _site_id}, _from, state), do: {:reply, {:error, :not_found}, state}

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
        broadcast(state, {:theme_editing_session_updated, state.revision})
        {:reply, {:ok, state}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  def handle_call({:update, _site_id, _attrs}, _from, state),
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

  def handle_call({:discard, site_id}, _from, %{site_id: site_id, status: :editing} = state) do
    close(state, :ok, :discarded)
  end

  def handle_call({:discard, site_id}, _from, %{site_id: site_id} = state),
    do: {:reply, {:error, :publishing}, state}

  def handle_call({:discard, _site_id}, _from, state),
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

  def handle_info(:expire, %{status: :publishing} = state) do
    Process.send_after(self(), :expire, to_timeout(second: 1))
    {:noreply, state}
  end

  def handle_info(:expire, state) do
    broadcast(state, {:theme_editing_session_closed, :expired})
    {:stop, :normal, state}
  end

  defp close(state, reply, reason) do
    broadcast(state, {:theme_editing_session_closed, reason})
    {:stop, :normal, reply, state}
  end

  defp release_publisher(%{publisher: {_publisher, monitor}} = state) do
    Process.demonitor(monitor, [:flush])
    %{state | status: :editing, publisher: nil}
  end

  defp broadcast(state, message),
    do: Phoenix.PubSub.broadcast(Gesttalt.PubSub, ThemeEditing.topic(state.id), message)

  defp claim_slot(site_id) do
    Enum.reduce_while(1..@max_sessions_per_site, {:error, :too_many_sessions}, fn slot, error ->
      case Registry.register(Gesttalt.ThemeEditing.SlotRegistry, {site_id, slot}, nil) do
        {:ok, _owner} -> {:halt, {:ok, slot}}
        {:error, {:already_registered, _owner}} -> {:cont, error}
      end
    end)
  end

  defp via(session_id), do: {:via, Registry, {Gesttalt.ThemeEditing.SessionRegistry, session_id}}
end
