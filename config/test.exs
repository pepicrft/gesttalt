import Config

test_port = String.to_integer(System.get_env("GESTTALT_TEST_PORT", "4002"))

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gesttalt, Gesttalt.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    System.get_env(
      "GESTTALT_TEST_DATABASE_NAME",
      "gesttalt_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :gesttalt,
  platform_host: "gesttalt.test",
  uploads_dir: Path.join(System.tmp_dir!(), "gesttalt-test-uploads"),
  stripe: []

config :gesttalt, Gesttalt.Mailer, adapter: Swoosh.Adapters.Test

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gesttalt, GesttaltWeb.Endpoint,
  url: [host: "localhost", port: test_port, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: test_port],
  secret_key_base: "VayTzP4JVum4Ywxqiw9aO6m3Ik5RQzw5OahDAwjKJsvyV4hJ2WX12ousO/L02D4S",
  server: false

config :boruta, Boruta.Oauth, issuer: "http://localhost:#{test_port}"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
