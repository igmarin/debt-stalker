defmodule DebtStalker.Countries.CO do
  @moduledoc """
  Colombia (CO) country module.

  Implements Cédula de Ciudadanía (CC) validation (8-10 numeric digits),
  financial threshold checks (debt-to-income ratio per requirements §3.2),
  and Datacredito-based provider summary interpretation.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @income_multiplier 12
  @debt_multiplier 22
  @datacredito_threshold 580

  @doc "Validates a Colombian Cédula de Ciudadanía (8-10 numeric digits, no checksum letter)."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, String.t()}
  def validate_document(document) do
    trimmed = String.trim(document)
    length = String.length(trimmed)

    cond do
      length < 8 ->
        {:error, "invalid CC format: must be 8-10 numeric digits"}

      length > 10 ->
        {:error, "invalid CC format: must be 8-10 numeric digits"}

      not String.match?(trimmed, ~r/^\d{8,10}$/) ->
        {:error, "invalid CC format: must contain only numeric digits"}

      true ->
        :ok
    end
  end

  @doc "Checks financial thresholds for Colombia and returns review flags."
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

  @doc "Interprets a normalized provider summary for Colombian risk evaluation."
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

  @doc "Returns whether the Datacredito risk score is acceptable for Colombia (≥ 580)."
  @impl true
  @spec acceptable_risk_score?(map()) :: boolean()
  def acceptable_risk_score?(%{"risk_indicators" => %{"datacredito_score" => score}})
      when is_integer(score) do
    score >= @datacredito_threshold
  end

  def acceptable_risk_score?(_provider_summary), do: false

  @doc "Returns the allowed status transitions for Colombia."
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

  @doc "Returns the minimum acceptable Datacredito score for Colombia."
  @impl true
  @spec risk_score_threshold() :: non_neg_integer()
  def risk_score_threshold, do: @datacredito_threshold

  @doc "Returns a short document hint for Colombian forms."
  @impl true
  @spec document_hint() :: String.t()
  def document_hint, do: "1234567890 (Cédula)"

  @doc "Returns the currency symbol for Colombia."
  @impl true
  @spec currency_symbol() :: String.t()
  def currency_symbol, do: "$"

  @doc "Generates a random valid Colombian CC (8-10 digits) for demo/seed data."
  @spec random_identity_document() :: String.t()
  def random_identity_document do
    length = Enum.random(8..10)

    :rand.uniform(:math.pow(10, length) |> trunc() |> Kernel.-(1))
    |> Integer.to_string()
    |> String.pad_leading(length, "0")
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
