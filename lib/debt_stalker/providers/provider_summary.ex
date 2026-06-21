defmodule DebtStalker.Providers.ProviderSummary do
  @moduledoc """
  Normalized provider summary struct.

  Contains only normalized fields — raw payloads are never stored or returned.
  """

  @typedoc "Normalized provider summary struct."
  @type t :: %__MODULE__{
          provider_status: String.t(),
          risk_indicators: map(),
          normalized_data: map()
        }

  @enforce_keys [:provider_status, :risk_indicators, :normalized_data]
  defstruct [:provider_status, :risk_indicators, :normalized_data]

  @doc "Creates a new normalized provider summary from a map of attributes."
  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      provider_status: Map.fetch!(attrs, :provider_status),
      risk_indicators: Map.get(attrs, :risk_indicators, %{}),
      normalized_data: Map.get(attrs, :normalized_data, %{})
    }
  end

  @doc "Serializes a provider summary to a plain map for persistence or responses."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = summary) do
    %{
      "provider_status" => summary.provider_status,
      "risk_indicators" => summary.risk_indicators,
      "normalized_data" => summary.normalized_data
    }
  end
end
