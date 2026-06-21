defmodule DebtStalker.Application do
  @moduledoc """
  OTP application supervisor for DebtStalker.

  Starts the repository, PubSub, Oban, web endpoint, and other
  top-level supervision tree children.
  """

  use Application

  @doc "Starts the DebtStalker OTP supervision tree."
  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      DebtStalkerWeb.Telemetry,
      DebtStalker.Vault,
      DebtStalker.Repo,
      {DNSCluster, query: Application.get_env(:debt_stalker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DebtStalker.PubSub},
      DebtStalker.Countries.Registry,
      {Oban, Application.fetch_env!(:debt_stalker, Oban)},
      DebtStalkerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DebtStalker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc "Propagates runtime configuration changes to the endpoint."
  @impl true
  @spec config_change([{atom(), term()}], [{atom(), term()}], [atom()]) :: :ok
  def config_change(changed, _new, removed) do
    DebtStalkerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
