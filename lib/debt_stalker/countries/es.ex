defmodule DebtStalker.Countries.ES do
  @moduledoc """
  Spain (ES) country module.

  Implements DNI validation (8 digits + checksum letter), financial threshold
  checks (amount > 15000 and amount > 12x income flag for review),
  and provider summary interpretation.
  """
  @behaviour DebtStalker.Countries.Behaviour

  @dni_letters "TRWAGMYFPDXBNJZSQVHLCKE"
  @amount_threshold Decimal.new("15000")
  @income_multiplier 12

  @doc "Validates a Spanish DNI (8 digits + checksum letter)."
  @impl true
  @spec validate_document(String.t()) :: :ok | {:error, String.t()}
  def validate_document(document) do
    trimmed = String.trim(document)

    with {:ok, {digits, letter}} <- parse_dni(trimmed) do
      verify_checksum(digits, letter)
    end
  end

  @doc "Checks financial thresholds for Spain and returns review flags."
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

  @doc "Interprets a normalized provider summary for Spanish risk evaluation."
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

  @doc "Returns whether the provider risk score is acceptable for Spain."
  @impl true
  @spec acceptable_risk_score?(map()) :: boolean()
  def acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => score}})
      when is_integer(score) do
    score >= 650
  end

  def acceptable_risk_score?(_provider_summary), do: false

  @doc "Returns the allowed status transitions for Spain."
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

  defp parse_dni(document) when byte_size(document) == 9 do
    digits_str = String.slice(document, 0, 8)
    letter = String.at(document, 8)

    if String.match?(digits_str, ~r/^\d{8}$/) and String.match?(letter, ~r/^[A-Z]$/) do
      {:ok, {String.to_integer(digits_str), letter}}
    else
      {:error, "invalid DNI format: must be 8 digits followed by one uppercase letter"}
    end
  end

  defp parse_dni(_document) do
    {:error, "invalid DNI format: must be exactly 9 characters (8 digits + 1 letter)"}
  end

  defp verify_checksum(digits, letter) do
    expected_index = rem(digits, 23)
    expected_letter = String.at(@dni_letters, expected_index)

    if letter == expected_letter do
      :ok
    else
      {:error, "invalid DNI checksum: expected #{expected_letter}, got #{letter}"}
    end
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
