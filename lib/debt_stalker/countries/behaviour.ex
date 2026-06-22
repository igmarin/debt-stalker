defmodule DebtStalker.Countries.Behaviour do
  @moduledoc """
  Behaviour contract for country-specific validation and risk rules.

  Each country module (ES, MX, etc.) implements this behaviour to provide:
  - Document format validation
  - Financial threshold checks
  - Provider summary interpretation
  - Allowed status transitions (can narrow the global set)
  """

  @typedoc "Result of validating an identity document."
  @type validation_result :: :ok | {:error, String.t()}

  @typedoc "Result of validating financial thresholds."
  @type financial_result :: %{additional_review_required: boolean(), reasons: [String.t()]}

  @doc "Validates the identity document format for this country."
  @callback validate_document(document :: String.t()) :: validation_result()

  @doc "Validates financial thresholds and returns review flags."
  @callback validate_financials(params :: map()) :: financial_result()

  @doc "Interprets normalized provider summary for risk evaluation."
  @callback interpret_provider_summary(summary :: map()) :: map()

  @doc "Returns whether additional review is required given the application params."
  @callback additional_review_required?(params :: map()) :: boolean()

  @doc "Returns whether the provider risk score is acceptable for this country."
  @callback acceptable_risk_score?(provider_summary :: map()) :: boolean()

  @doc "Returns the allowed status transitions for this country (narrows global set)."
  @callback allowed_status_transitions() :: %{String.t() => [String.t()]}

  @doc "Returns the minimum acceptable risk score for this country."
  @callback risk_score_threshold() :: non_neg_integer()

  @doc "Returns a short example/hint for the identity document field in UI forms."
  @callback document_hint() :: String.t()

  @doc ~S|Returns the currency symbol for this country (e.g. "$", "€").|
  @callback currency_symbol() :: String.t()

  @optional_callbacks [acceptable_risk_score?: 1, document_hint: 0]
end
