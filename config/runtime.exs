import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gesttalt start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("GESTTALT_PHX_SERVER") || System.get_env("PHX_SERVER") do
  config :gesttalt, GesttaltWeb.Endpoint, server: true
end

runtime_port =
  case config_env() do
    :test -> String.to_integer(System.get_env("GESTTALT_TEST_PORT", "4002"))
    _environment -> String.to_integer(System.get_env("GESTTALT_PORT", "4000"))
  end

config :gesttalt, GesttaltWeb.Endpoint, http: [port: runtime_port]

if config_env() == :prod do
  database_url =
    System.get_env("GESTTALT_DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gesttalt, Gesttalt.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("GESTTALT_POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("GESTTALT_SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("GESTTALT_HOST") || "gesttalt.org"

  config :gesttalt,
    dns_cluster_query: System.get_env("GESTTALT_DNS_CLUSTER_QUERY"),
    platform_host: host,
    uploads_dir: System.get_env("GESTTALT_UPLOADS_DIR", "/app/uploads"),
    agent_auth: [
      claim_ttl_seconds: 600,
      poll_interval_seconds: 5,
      assertion_ttl_seconds: 86_400,
      private_key_pem: System.get_env("GESTTALT_AGENT_AUTH_PRIVATE_KEY_PEM"),
      allow_ephemeral_signing_key: false
    ],
    stripe: [
      secret_key: System.get_env("GESTTALT_STRIPE_SECRET_KEY"),
      price_id: System.get_env("GESTTALT_STRIPE_PRICE_ID"),
      webhook_secret: System.get_env("GESTTALT_STRIPE_WEBHOOK_SECRET"),
      monthly_price_euros:
        String.to_integer(System.get_env("GESTTALT_STRIPE_MONTHLY_PRICE_EUROS", "5")),
      automatic_tax: System.get_env("GESTTALT_STRIPE_AUTOMATIC_TAX", "false") in ~w(true 1)
    ]

  config :boruta, Boruta.Oauth, issuer: "https://#{host}"

  config :gesttalt, Gesttalt.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("GESTTALT_SMTP_RELAY", "smtp-relay.smtp-relay.svc.cluster.local"),
    port: String.to_integer(System.get_env("GESTTALT_SMTP_PORT", "25")),
    auth: :never,
    tls: :never,
    retries: 2,
    no_mx_lookups: true

  config :gesttalt, GesttaltWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gesttalt, GesttaltWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :gesttalt, GesttaltWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
