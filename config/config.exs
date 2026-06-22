# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :debt_stalker,
  ecto_repos: [DebtStalker.Repo],
  generators: [timestamp_type: :utc_datetime]

config :debt_stalker, DebtStalkerWeb.Gettext,
  default_locale: "es",
  locales: ~w(es en)

# Configure the endpoint
config :debt_stalker, DebtStalkerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DebtStalkerWeb.ErrorHTML, json: DebtStalkerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DebtStalker.PubSub,
  session_signing_salt: System.get_env("SESSION_SIGNING_SALT", "dev-session-signing-salt"),
  live_view: [
    signing_salt: System.get_env("LIVE_VIEW_SIGNING_SALT", "dev-live-view-signing-salt")
  ]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :debt_stalker, DebtStalker.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  debt_stalker: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  debt_stalker: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger — structured JSON via logger_json (all environments)
config :logger, :default_handler, formatter: {LoggerJSON.Formatters.Basic, metadata: :all}

# Register metadata keys used across the application (Credo + logger_json)
config :logger, :default_formatter,
  metadata: [
    :application_id,
    :country,
    :status,
    :from_status,
    :to_status,
    :from_state,
    :to_state,
    :worker,
    :event_id,
    :event_type,
    :event_count,
    :notification_status,
    :reason,
    :error_module,
    :error_message,
    :step
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Hammer rate limiter (ETS backend)
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

# Rate limit configuration (per-IP, sliding window)
# Limits are configurable via env vars in runtime.exs
config :debt_stalker, :rate_limit,
  auth_token: [limit: 10, window_ms: 60_000],
  webhook: [limit: 20, window_ms: 60_000]

# App cache TTL (milliseconds). The cache stores the full
# CreditApplication struct (including decrypted PII) in memory.
# A short TTL limits the PII exposure window and bounds staleness
# if an update path bypasses explicit invalidation.
config :debt_stalker, :app_cache_ttl_ms, :timer.seconds(60)

# Configure Oban
config :debt_stalker, Oban,
  repo: DebtStalker.Repo,
  queues: [default: 10, events: 20, notifications: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", DebtStalker.Workers.EventDispatcherWorker}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
