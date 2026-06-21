defmodule DebtStalker.Countries.MX do
  @moduledoc """
  Mexico (MX) country module.

  Implements CURP validation (18-char uppercase alphanumeric with structure),
  financial threshold checks (amount > 10x income, debt+amount > 18x income),
  and provider summary interpretation.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @income_multiplier 10
  @debt_multiplier 18

  @doc "Validates a Mexican CURP (18-character uppercase alphanumeric)."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, String.t()}
  def validate_document(document) do
    trimmed = String.trim(document)

    cond do
      String.length(trimmed) != 18 ->
        {:error, "invalid CURP format: must be exactly 18 characters"}

      not String.match?(trimmed, ~r/^[A-Z]{4}\d{6}[A-Z0-9]{6}[A-Z0-9]{2}$/) ->
        {:error,
         "invalid CURP format: must be 4 uppercase letters + 6 digits + 8 alphanumeric chars"}

      true ->
        :ok
    end
  end

  @doc "Checks financial thresholds for Mexico and returns review flags."
  @impl true
  @spec validate_financials(map()) :: %{
          additional_review_required: boolean(),
          reasons: [String.t()]
        }
  def validate_financials(params) do
    amount = Map.fetch!(params, :requested_amount)
    income = Map.fetch!(params, :monthly_income)
    provider_debt = Map.get(params, :provider_debt, Decimal.new("0"))

    reasons =
      []
      |> maybe_flag_income_ratio(amount, income)
      |> maybe_flag_debt_ratio(amount, income, provider_debt)

    %{additional_review_required: reasons != [], reasons: reasons}
  end

  @doc "Interprets a normalized provider summary for Mexican risk evaluation."
  @impl true
  @spec interpret_provider_summary(map()) :: map()
  def interpret_provider_summary(summary), do: summary

  @doc "Returns whether additional review is required for the given params."
  @impl true
  @spec additional_review_required?(map()) :: boolean()
  def additional_review_required?(params) do
    %{additional_review_required: required} = validate_financials(params)
    required
  end

  @doc "Returns whether the provider risk score is acceptable for Mexico."
  @impl true
  @spec acceptable_risk_score?(map()) :: boolean()
  def acceptable_risk_score?(%{"risk_indicators" => %{"buro_score" => score}})
      when is_integer(score) do
    score >= 600
  end

  def acceptable_risk_score?(_provider_summary), do: false

  @doc "Returns the allowed status transitions for Mexico."
  @impl true
  @spec allowed_status_transitions() :: %{String.t() => [String.t()]}
  def allowed_status_transitions do
    %{
      "submitted" => ["pending_risk", "provider_error", "cancelled"],
      "pending_risk" => ["additional_review", "approved", "rejected", "cancelled"],
      "additional_review" => ["approved", "rejected"],
      "provider_error" => ["pending_risk", "rejected"]
    }
  end

  # Private

  defp maybe_flag_income_ratio(reasons, amount, income) do
    threshold = Decimal.mult(income, @income_multiplier)

    if Decimal.gt?(amount, threshold) do
      ["income_ratio_exceeded" | reasons]
    else
      reasons
    end
  end

  defp maybe_flag_debt_ratio(reasons, amount, income, provider_debt) do
    total_debt = Decimal.add(provider_debt, amount)
    threshold = Decimal.mult(income, @debt_multiplier)

    if Decimal.gt?(total_debt, threshold) do
      ["debt_ratio_exceeded" | reasons]
    else
      reasons
    end
  end
end
