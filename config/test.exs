import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :debt_stalker, DebtStalker.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "debt_stalker_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :debt_stalker, DebtStalkerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "6Ze5EX+3CKJz475r8z2WCwoCaNnMrJITGum+ltLApg7CKqwrUMvbJNURBZWf2aPP",
  server: false

# In test we don't send emails
config :debt_stalker, DebtStalker.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable Oban job processing in tests (manual mode for assert_enqueued)
config :debt_stalker, Oban, testing: :manual

# Fixed existing_debt for known CURPs in MX adapter simulations (test-only)
config :debt_stalker, :mx_simulated_debt_overrides, %{
  "DEBT850101HDFRRL09" => 35_000
}

# Circuit breaker settings for tests (high threshold avoids cross-test pollution in async suite)
config :debt_stalker, :circuit_breakers,
  failure_threshold: 100,
  cooldown_ms: 5_000,
  retry_budget: 1,
  base_backoff_ms: 1

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Cloak encryption key (test only — same as dev, NOT for production)
config :debt_stalker, DebtStalker.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("7hFmtojiHGfMrgdBDBDIsMAlIA1Jmo5Up0vI2wuUdWQ="),
      iv_length: 12
    }
  ]
