defmodule DebtStalker.Countries.MX do
  @moduledoc """
  Mexico (MX) country module.

  Implements CURP validation (18-char uppercase alphanumeric with structure),
  financial threshold checks (amount > 10x income, debt+amount > 18x income),
  and provider summary interpretation.

  Document validation is delegated to `DebtStalker.Countries.Curp`.
  See https://github.com/igmarin/debt-stalker/issues/122 for future hardening work.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @income_multiplier 10
  @debt_multiplier 18

  @doc "Validates a Mexican CURP using the strict pre-validation rules."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, atom()}
  def validate_document(document) do
    validate_document(document, [])
  end

  @impl true
  @spec validate_document(String.t(), keyword()) :: :ok | {:error, atom()}
  def validate_document(document, opts) do
    DebtStalker.Countries.Curp.validate(document, opts)
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

  @doc "Returns the minimum acceptable risk score (buro_score) for Mexico."
  @impl true
  @spec risk_score_threshold() :: non_neg_integer()
  def risk_score_threshold, do: 600

  @doc "Returns a random valid CURP for demo/seed data (strict rules)."
  @spec random_identity_document() :: String.t()
  def random_identity_document do
    # Use a small pool of known good patterns to guarantee validation passes in seeds/tests
    base =
      Enum.random([
        "GARC850101HDFRRL09",
        "HEGG560427MVZRRL04",
        "MAMA750530HDFRRN08"
      ])

    # Vary last few chars slightly while keeping structure valid enough for demo
    prefix = String.slice(base, 0, 15)
    century = if :rand.uniform(2) == 1, do: Enum.random(?0..?9), else: Enum.random(?A..?Z)
    check = Enum.random(?0..?9)
    prefix <> <<century>> <> <<check>>
  end

  @doc "Returns a short document hint for Mexican forms."
  @impl true
  @spec document_hint() :: String.t()
  def document_hint, do: "GARC850101HDFRRL09 (CURP)"

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
