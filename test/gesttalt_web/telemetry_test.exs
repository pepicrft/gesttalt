defmodule GesttaltWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias Telemetry.Metrics.{Counter, Distribution, LastValue, Sum}

  test "exports supported web, database, and virtual-machine metrics" do
    metrics = GesttaltWeb.Telemetry.exporter_metrics()

    assert Enum.all?(
             metrics,
             &(Map.fetch!(&1, :__struct__) in [Counter, Distribution, LastValue, Sum])
           )

    assert metric(metrics, Counter, [:phoenix, :endpoint, :stop, :count])
    assert metric(metrics, Distribution, [:gesttalt, :repo, :query, :query_time])
    assert metric(metrics, LastValue, [:vm, :memory, :total])
  end

  test "production config installs the OpenTelemetry log handler and batch exporters" do
    config = Config.Reader.read!("config/prod.exs")

    gesttalt_config = Keyword.fetch!(config, :gesttalt)
    logger_handlers = Keyword.fetch!(gesttalt_config, :logger)

    assert [
             {:handler, :gesttalt_opentelemetry, OtelMetricExporter.LogHandler, _handler_config}
           ] = logger_handlers

    assert :batch = config_value(config, :opentelemetry, :span_processor)
    assert :http_protobuf = config_value(config, :opentelemetry_exporter, :otlp_protocol)
    assert :gzip = config_value(config, :opentelemetry_exporter, :otlp_compression)
    assert :http_protobuf = config_value(config, :otel_metric_exporter, :otlp_protocol)
    assert :gzip = config_value(config, :otel_metric_exporter, :otlp_compression)
  end

  defp metric(metrics, module, name) do
    Enum.find(metrics, &match?(%{__struct__: ^module, name: ^name}, &1))
  end

  defp config_value(config, application, key) do
    config
    |> Keyword.fetch!(application)
    |> Keyword.fetch!(key)
  end
end
