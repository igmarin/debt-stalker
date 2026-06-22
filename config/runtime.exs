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
    secret_key_base: secret_key_base,
    session_signing_salt:
      System.get_env("SESSION_SIGNING_SALT") ||
        raise """
        environment variable SESSION_SIGNING_SALT is missing.
        Generate one with: mix phx.gen.secret 16
        """


  # JWT secret for token verification (required in prod)
  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      environment variable JWT_SECRET is missing.
      Generate one with: mix phx.gen.secret 64
      """

  config :debt_stalker, :jwt_secret, jwt_secret

  # Admin password for the browser companion UI (required in prod)
  admin_password =
    System.get_env("ADMIN_PASSWORD") ||
      raise """
      environment variable ADMIN_PASSWORD is missing.
      Set a strong password for the admin dashboard.
      """

  config :debt_stalker, :admin_password, admin_password

  # Oban queues (configurable via env)
  # Set OBAN_QUEUES=false to disable all queues (web deployment).
  # Set individual queue sizes for worker deployment.
  oban_queues =
    case System.get_env("OBAN_QUEUES", "") do
      "false" ->
        false

      _ ->
        [
          default: String.to_integer(System.get_env("OBAN_QUEUE_DEFAULT", "10")),
          events: String.to_integer(System.get_env("OBAN_QUEUE_EVENTS", "20")),
          notifications: String.to_integer(System.get_env("OBAN_QUEUE_NOTIFICATIONS", "10"))
        ]
    end

  config :debt_stalker, Oban,
    repo: DebtStalker.Repo,
    queues: oban_queues

  # Log level
  config :logger, level: String.to_existing_atom(System.get_env("LOG_LEVEL", "info"))

  # Cloak encryption key (required in prod)
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate a 32-byte key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """

  config :debt_stalker, DebtStalker.Vault,
    ciphers: [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: "AES.GCM.V1", key: Base.decode64!(cloak_key), iv_length: 12
      }
    ]

  # Webhook HMAC secret (required in prod)
  webhook_secret =
    System.get_env("WEBHOOK_SECRET") ||
      raise """
      environment variable WEBHOOK_SECRET is missing.
      Set a strong secret for inbound webhook signature verification.
      """

  config :debt_stalker, :webhook_secret, webhook_secret
  config :debt_stalker, :require_webhook_signature, true

  # LiveView signing salt (required in prod)
  live_view_signing_salt =
    System.get_env("LIVE_VIEW_SIGNING_SALT") ||
      raise """
      environment variable LIVE_VIEW_SIGNING_SALT is missing.
      Generate one with: mix phx.gen.secret 32
      """

  config :debt_stalker, DebtStalkerWeb.Endpoint,
    live_view: [signing_salt: live_view_signing_salt]

  # Rate limits (configurable via env, per-IP sliding window)
  config :debt_stalker, :rate_limit,
    auth_token: [
      limit: String.to_integer(System.get_env("RATE_LIMIT_AUTH_TOKEN", "10")),
      window_ms: String.to_integer(System.get_env("RATE_LIMIT_AUTH_TOKEN_WINDOW_MS", "60000"))
    ],
    webhook: [
      limit: String.to_integer(System.get_env("RATE_LIMIT_WEBHOOK", "20")),
      window_ms: String.to_integer(System.get_env("RATE_LIMIT_WEBHOOK_WINDOW_MS", "60000"))
    ]

  # App cache TTL (configurable via env, milliseconds, default 60s)
  config :debt_stalker,
         :app_cache_ttl_ms,
         String.to_integer(System.get_env("APP_CACHE_TTL_MS", "60000"))
end

# Dev/test JWT secret, webhook secret, and admin password
# (not sensitive — development only)
if config_env() in [:dev, :test] do
  config :debt_stalker, :jwt_secret, "dev-jwt-secret-not-for-production"
  config :debt_stalker, :admin_password, System.get_env("ADMIN_PASSWORD", "admin123")

  config :debt_stalker, :webhook_secret,
    System.get_env("WEBHOOK_SECRET", "dev-webhook-secret")

  config :debt_stalker, :require_webhook_signature, false

  config :debt_stalker, DebtStalkerWeb.Endpoint,
    live_view: [signing_salt: "dev-live-view-signing-salt"]
end
