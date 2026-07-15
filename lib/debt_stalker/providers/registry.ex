defmodule DebtStalker.Providers.Registry do
  @moduledoc """
  ETS-backed registry for provider adapters.

  Caches the country code → adapter module mapping at boot time for O(1)
  lookups. Resolves configured country codes to their respective simulated adapters.
  """
  use GenServer

  @table_name :provider_registry

  @doc "Looks up the provider adapter module for the given country code."
  @spec lookup(String.t()) :: {:ok, module()} | {:error, :unsupported_provider}
  def lookup(country_code) do
    case :ets.lookup(@table_name, country_code) do
      [{^country_code, module}] -> {:ok, module}
      [] -> {:error, :unsupported_provider}
    end
  end

  @doc "Returns the list of supported provider country codes."
  @spec supported_providers() :: [String.t()]
  def supported_providers do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {code, _module} -> code end)
    |> Enum.sort()
  end

  # GenServer

  @doc "Starts the provider registry GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initializes the ETS table and loads configured providers."
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, read_concurrency: true])
    load_providers(table)
    {:ok, %{table: table}}
  end

  defp load_providers(table) do
    providers = Application.get_env(:debt_stalker, :providers, default_providers())

    Enum.each(providers, fn {code, module} ->
      :ets.insert(table, {code, module})
    end)
  end

  defp default_providers do
    [
      {"ES", DebtStalker.Providers.ESAdapter},
      {"MX", DebtStalker.Providers.MXAdapter},
      {"PL", DebtStalker.Providers.PLAdapter}
    ]
  end
end
