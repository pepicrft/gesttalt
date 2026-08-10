defmodule Gesttalt.Analytics.CountryDatabase do
  @moduledoc false

  use GenServer

  alias Gesttalt.Analytics.Location

  @refresh_interval :timer.hours(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok)

  @impl true
  def init(:ok) do
    send(self(), :refresh)
    {:ok, nil}
  end

  @impl true
  def handle_info(:refresh, previous_url) do
    url = Location.database_url()

    if url != previous_url do
      Location.reload_database(url)
    end

    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, url}
  end
end
