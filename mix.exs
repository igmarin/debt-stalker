defmodule DebtStalker.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :debt_stalker,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit, :credo]
      ],
      docs: [
        main: "DebtStalker",
        extras: ["CHANGELOG.md"]
      ],
      test_coverage: [
        summary: [threshold: 85],
        ignore_modules: coverage_ignore_modules()
      ]
    ]
  end

  defp coverage_ignore_modules do
    [
      DebtStalker.Mailer,
      DebtStalkerWeb.CoreComponents,
      DebtStalkerWeb.Endpoint,
      DebtStalkerWeb.ErrorHTML,
      DebtStalkerWeb.Gettext,
      DebtStalkerWeb.Layouts,
      DebtStalkerWeb.PageHTML
    ]
  end

  def application do
    [
      mod: {DebtStalker.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Web framework
      {:phoenix, "~> 1.8.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry_metrics_prometheus, "~> 1.1"},
      {:gettext, "~> 1.0"},
      {:contex, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Background jobs
      {:oban, "~> 2.18"},

      # JWT authentication
      {:joken, "~> 2.6"},

      # PII encryption at rest
      {:cloak_ecto, "~> 1.3"},

      # Structured JSON logging
      {:logger_json, "~> 6.0"},

      # Code quality (dev/test)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},

      # Testing
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind debt_stalker", "esbuild debt_stalker"],
      "assets.deploy": [
        "tailwind debt_stalker --minify",
        "esbuild debt_stalker --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
