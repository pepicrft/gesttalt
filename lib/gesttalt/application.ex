defmodule Gesttalt.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GesttaltWeb.Telemetry,
      Gesttalt.Repo,
      {DNSCluster, query: Application.get_env(:gesttalt, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gesttalt.PubSub},
      {Registry, keys: :unique, name: Gesttalt.ThemeEditing.SessionRegistry},
      {Registry, keys: :unique, name: Gesttalt.ThemeEditing.SlotRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Gesttalt.ThemeEditing.SessionSupervisor},
      # Start a worker by calling: Gesttalt.Worker.start_link(arg)
      # {Gesttalt.Worker, arg},
      # Start to serve requests, typically the last entry
      GesttaltWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gesttalt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GesttaltWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
