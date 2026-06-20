import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

if System.get_env("PHX_SERVER") do
  config :debt_stalker, DebtStalkerWeb.Endpoint, server: true
end

config :debt_stalker, DebtStalkerWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :debt_stalker, DebtStalker.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :debt_stalker, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :debt_stalker, DebtStalkerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # JWT secret for token verification (required in prod)
  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      environment variable JWT_SECRET is missing.
      Generate one with: mix phx.gen.secret 64
      """

  config :debt_stalker, :jwt_secret, jwt_secret

  # Oban queues (configurable via env)
  config :debt_stalker, Oban,
    repo: DebtStalker.Repo,
    queues: [
      default: String.to_integer(System.get_env("OBAN_QUEUE_DEFAULT", "10")),
      events: String.to_integer(System.get_env("OBAN_QUEUE_EVENTS", "20")),
      notifications: String.to_integer(System.get_env("OBAN_QUEUE_NOTIFICATIONS", "10"))
    ]

  # Log level
  config :logger, level: String.to_existing_atom(System.get_env("LOG_LEVEL", "info"))
end

# Dev/test JWT secret (not sensitive — development only)
if config_env() in [:dev, :test] do
  config :debt_stalker, :jwt_secret, "dev-jwt-secret-not-for-production"
end
