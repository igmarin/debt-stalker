defmodule DebtStalker.Providers.CircuitBreakers do
  @moduledoc """
  Boots and resolves per-country provider circuit breakers.

  Each supported provider country gets a dedicated `CircuitBreaker` process.
  Lookups are served from an ETS table for O(1) access.
  """

  use GenServer

  alias DebtStalker.Providers.CircuitBreaker
  alias DebtStalker.Providers.Registry, as: ProviderRegistry

  @table_name :circuit_breaker_registry

  @doc "Starts the circuit breaker registry GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Resets all country circuit breakers to closed state. Used to isolate tests."
  @spec reset_all() :: :ok
  def reset_all do
    ProviderRegistry.supported_providers()
    |> Enum.each(fn country ->
      {:ok, pid} = lookup(country)
      CircuitBreaker.reset(pid)
    end)

    :ok
  end

  @doc "Returns the circuit breaker pid for a provider country code."
  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :unsupported_provider}
  def lookup(country_code) do
    case :ets.lookup(@table_name, country_code) do
      [{^country_code, pid}] -> {:ok, pid}
      [] -> {:error, :unsupported_provider}
    end
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, read_concurrency: true])
    config = circuit_breaker_config()

    ProviderRegistry.supported_providers()
    |> Enum.each(fn country ->
      {:ok, adapter} = ProviderRegistry.lookup(country)
      {:ok, pid} = CircuitBreaker.start_link(config)

      CircuitBreaker.set_adapter(pid, {adapter, :fetch, [country]})
      :ets.insert(table, {country, pid})
    end)

    {:ok, %{table: table}}
  end

  @spec circuit_breaker_config() :: map()
  defp circuit_breaker_config do
    :debt_stalker
    |> Application.get_env(:circuit_breakers, [])
    |> Map.new()
    |> then(fn overrides ->
      Map.merge(
        %{
          failure_threshold: 5,
          cooldown_ms: 30_000,
          retry_budget: 3,
          base_backoff_ms: 100
        },
        overrides
      )
    end)
  end
end
