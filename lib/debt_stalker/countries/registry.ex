defmodule DebtStalker.Countries.Registry do
  @moduledoc """
  ETS-backed registry for country modules.

  Caches the country code → module mapping at boot time for O(1) lookups.
  Resolves configured country codes to their respective implementation modules.
  """
  use GenServer

  @table_name :country_registry

  @doc "Looks up the country module for the given ISO country code."
  @spec lookup(String.t()) :: {:ok, module()} | {:error, :unsupported_country}
  def lookup(country_code) do
    case :ets.lookup(@table_name, country_code) do
      [{^country_code, module}] -> {:ok, module}
      [] -> {:error, :unsupported_country}
    end
  end

  @doc "Returns the list of supported country codes."
  @spec supported_countries() :: [String.t()]
  def supported_countries do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {code, _module} -> code end)
    |> Enum.sort()
  end

  # GenServer

  @doc "Starts the country registry GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initializes the ETS table and loads configured countries."
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, read_concurrency: true])
    load_countries(table)
    {:ok, %{table: table}}
  end

  defp load_countries(table) do
    countries = Application.get_env(:debt_stalker, :countries, default_countries())

    Enum.each(countries, fn {code, module} ->
      :ets.insert(table, {code, module})
    end)
  end

  defp default_countries do
    [
      {"ES", DebtStalker.Countries.ES},
      {"MX", DebtStalker.Countries.MX},
      {"PL", DebtStalker.Countries.PL}
    ]
  end
end
