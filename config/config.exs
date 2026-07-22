# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :boruta, Boruta.Oauth,
  repo: Gesttalt.Repo,
  issuer: "http://localhost:4000",
  contexts: [
    resource_owners: Gesttalt.OAuth.ResourceOwners,
    clients: Gesttalt.OAuth.Clients
  ]

config :gesttalt, :scopes,
  user: [
    default: true,
    module: Gesttalt.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Gesttalt.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :gesttalt,
  ecto_repos: [Gesttalt.Repo],
  generators: [timestamp_type: :utc_datetime],
  observability_enabled: false,
  platform_host: "gesttalt.org",
  seed_demo: false,
  media_storage: [
    adapter: Gesttalt.MediaStorage.Local,
    uploads_dir: Path.expand("../priv/uploads", __DIR__)
  ],
  agent_auth: [
    registration_ttl_seconds: 86_400,
    claim_attempt_ttl_seconds: 600,
    poll_interval_seconds: 5,
    assertion_ttl_seconds: 86_400,
    allow_ephemeral_signing_key: true
  ],
  stripe: [monthly_price_euros: 5, automatic_tax: false]

config :gesttalt, Gesttalt.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Exporting stays disabled unless a production runtime provides an OpenTelemetry
# Protocol endpoint. This keeps local development and tests self-contained.
config :opentelemetry, traces_exporter: :none

# Configure the endpoint
config :gesttalt, GesttaltWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GesttaltWeb.ErrorHTML, json: GesttaltWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Gesttalt.PubSub,
  live_view: [signing_salt: "HIYSKRu8"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  gesttalt: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Elixir's built-in JSON module for parsing in Phoenix
config :phoenix, :json_library, JSON

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
