defmodule DebtStalker.Countries.PL do
  @moduledoc """
  Poland (PL) country module.

  Implements PESEL validation (11 digits with a weighted checksum), financial
  threshold checks (amount cap and amount-to-income ratio), and provider
  summary interpretation using the Polish BIK scoring key.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @pesel_weights [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]
  @amount_threshold Decimal.new("60000")
  @income_multiplier 10

  @doc "Validates a Polish PESEL (11 digits with a weighted checksum)."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, String.t()}
  def validate_document(document) do
    trimmed = String.trim(document)

    if String.match?(trimmed, ~r/^\d{11}$/) do
      verify_pesel_checksum(trimmed)
    else
      {:error, "invalid PESEL format: must be exactly 11 digits"}
    end
  end

  @doc "Checks financial thresholds for Poland and returns review flags."
  @impl true
  @spec validate_financials(map()) :: %{
          additional_review_required: boolean(),
          reasons: [String.t()]
        }
  def validate_financials(%{requested_amount: amount, monthly_income: income}) do
    reasons =
      []
      |> maybe_flag_amount(amount)
      |> maybe_flag_income_ratio(amount, income)

    %{additional_review_required: reasons != [], reasons: reasons}
  end

  @doc "Interprets a normalized provider summary for Polish risk evaluation."
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

  @doc "Returns whether the provider risk score is acceptable for Poland."
  @impl true
  @spec acceptable_risk_score?(map()) :: boolean()
  def acceptable_risk_score?(%{"risk_indicators" => %{"bik_score" => score}})
      when is_integer(score) do
    score >= 650
  end

  def acceptable_risk_score?(_provider_summary), do: false

  @doc "Returns the allowed status transitions for Poland."
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

  @doc "Returns the minimum acceptable risk score (bik_score) for Poland."
  @impl true
  @spec risk_score_threshold() :: non_neg_integer()
  def risk_score_threshold, do: 650

  @doc "Returns a random valid Polish PESEL for demo/seed data."
  @spec random_identity_document() :: String.t()
  def random_identity_document do
    digits = [Enum.random(1..8) | Enum.map(1..9, fn _ -> Enum.random(0..9) end)]
    checksum = pesel_checksum(digits)

    digits
    |> List.insert_at(-1, checksum)
    |> Enum.map_join(&Integer.to_string/1)
  end

  @doc "Returns a short document hint for Polish forms."
  @impl true
  @spec document_hint() :: String.t()
  def document_hint, do: "02070803628 (PESEL)"

  @doc "Returns the currency symbol for Poland."
  @impl true
  @spec currency_symbol() :: String.t()
  def currency_symbol, do: "zł"

  # Private

  defp verify_pesel_checksum(document) do
    digits = Enum.map(String.graphemes(document), &String.to_integer/1)
    checksum = pesel_checksum(digits)

    if List.last(digits) == checksum do
      :ok
    else
      {:error, "invalid PESEL checksum"}
    end
  end

  defp pesel_checksum(digits) do
    digits
    |> Enum.take(10)
    |> Enum.zip(@pesel_weights)
    |> Enum.map(fn {digit, weight} -> digit * weight end)
    |> Enum.sum()
    |> rem(10)
    |> then(fn remainder -> rem(10 - remainder, 10) end)
  end

  defp maybe_flag_amount(reasons, amount) do
    if Decimal.gt?(amount, @amount_threshold) do
      ["amount_exceeds_threshold" | reasons]
    else
      reasons
    end
  end

  defp maybe_flag_income_ratio(reasons, amount, income) do
    threshold = Decimal.mult(income, @income_multiplier)

    if Decimal.gt?(amount, threshold) do
      ["income_ratio_exceeded" | reasons]
    else
      reasons
    end
  end
end
