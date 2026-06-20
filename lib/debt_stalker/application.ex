defmodule DebtStalker.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DebtStalkerWeb.Telemetry,
      DebtStalker.Repo,
      {DNSCluster, query: Application.get_env(:debt_stalker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DebtStalker.PubSub},
      {Oban, Application.fetch_env!(:debt_stalker, Oban)},
      DebtStalkerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DebtStalker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DebtStalkerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
