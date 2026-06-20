defmodule DebtStalker.Providers.Behaviour do
  @moduledoc """
  Behaviour contract for country-specific provider adapters.

  Each provider adapter fetches banking/credit data from an external source
  (simulated in Phase 1), normalizes it into a standard summary, and returns
  structured results.
  """

  @type provider_error :: :timeout | :unavailable | :invalid_document | :rejection
  @type fetch_result :: {:ok, provider_summary()} | {:error, provider_error()}
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
