defmodule GesttaltWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      [
        # Telemetry poller will execute the given period measurements
        # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
        {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      ] ++ exporter_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp exporter_children do
    if Application.get_env(:gesttalt, :observability_enabled, false) do
      [{OtelMetricExporter, metrics: exporter_metrics(), export_period: :timer.seconds(15)}]
    else
      []
    end
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("gesttalt.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("gesttalt.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("gesttalt.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("gesttalt.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("gesttalt.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  def exporter_metrics do
    [
      counter("phoenix.endpoint.stop.count",
        event_name: [:phoenix, :endpoint, :stop],
        tags: [:method, :status],
        tag_values: &endpoint_tag_values/1,
        description: "Number of completed web requests"
      ),
      distribution("phoenix.endpoint.stop.duration",
        tags: [:method, :status],
        tag_values: &endpoint_tag_values/1,
        unit: {:native, :millisecond}
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      counter("phoenix.router_dispatch.exception.count",
        event_name: [:phoenix, :router_dispatch, :exception],
        tags: [:kind, :route]
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        tags: [:kind, :route],
        unit: {:native, :millisecond}
      ),
      distribution("phoenix.socket_connected.duration", unit: {:native, :millisecond}),
      sum("phoenix.socket_drain.count"),
      distribution("phoenix.channel_joined.duration", unit: {:native, :millisecond}),
      distribution("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),
      distribution("gesttalt.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other query measurements"
      ),
      distribution("gesttalt.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding data received from the database"
      ),
      distribution("gesttalt.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      distribution("gesttalt.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      distribution("gesttalt.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection waited before it was checked out"
      ),
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp endpoint_tag_values(%{conn: conn}) do
    %{method: conn.method, status: conn.status}
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {GesttaltWeb, :count_users, []}
    ]
  end
end
