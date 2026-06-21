defmodule DebtStalker.Providers.Behaviour do
  @moduledoc """
  Behaviour contract for country-specific provider adapters.

  Each provider adapter fetches banking/credit data from an external source
  (simulated in Phase 1), normalizes it into a standard summary, and returns
  structured results.
  """

  @typedoc "Possible errors returned by a provider adapter."
  @type provider_error :: :timeout | :unavailable | :invalid_document | :rejection

  @typedoc "Result of fetching provider data."
  @type fetch_result :: {:ok, provider_summary()} | {:error, provider_error()}

  @typedoc "Normalized provider summary map."
  @type provider_summary :: %{
          provider_status: String.t(),
          risk_indicators: map(),
          normalized_data: map()
        }

  @doc """
  Fetches and normalizes provider data for a given country and document.

  Returns a normalized summary on success, or a structured error.
  Raw payloads are never returned or persisted.
  """
  @callback fetch(country :: String.t(), params :: map()) :: fetch_result()
end
