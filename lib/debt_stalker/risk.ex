defmodule DebtStalker.Risk do
  @moduledoc """
  Risk evaluation context.

  Contains the business logic for evaluating credit application risk
  based on country-specific rules and provider summary data.

  This context is called by `DebtStalker.Workers.RiskEvaluationWorker` —
  workers delegate, never implement business logic (Code Org Contract §3.1).
  """

  alias DebtStalker.Applications.CreditApplication
  alias DebtStalker.Countries.Registry

  @doc """
  Evaluates risk for a credit application and returns the recommended
  next status.

  The evaluation considers:
  - Country-specific financial thresholds (additional review required)
  - Provider risk indicators (credit score / buro score)

  Returns `{:ok, status}` where status is one of:
  - `"approved"` — risk score acceptable, no additional review needed
  - `"additional_review"` — country thresholds exceeded
  - `"rejected"` — risk score below acceptable threshold

  Returns `{:error, :unsupported_country}` if the application's country
  is not registered.
  """
  @spec evaluate(CreditApplication.t()) ::
          {:ok, String.t()} | {:error, :unsupported_country}
  def evaluate(%CreditApplication{} = app) do
    with {:ok, country_module} <- Registry.lookup(app.country) do
      financials_params = %{
        requested_amount: app.requested_amount,
        monthly_income: app.monthly_income,
        provider_debt: extract_provider_debt(app.provider_summary)
      }

      review_required = country_module.additional_review_required?(financials_params)

      new_status =
        cond do
          review_required -> "additional_review"
          risk_score_acceptable?(app) -> "approved"
          true -> "rejected"
        end

      {:ok, new_status}
    end
  end

  @doc """
  Returns the acceptable risk score threshold for a given country.

  Uses `credit_score` for ES and `buro_score` for MX.
  """
  @spec risk_score_threshold(String.t()) :: non_neg_integer() | nil
  def risk_score_threshold(country) do
    case country do
      "ES" -> 650
      "MX" -> 600
      _ -> nil
    end
  end

  defp risk_score_acceptable?(app) do
    case app.provider_summary do
      %{"risk_indicators" => %{"credit_score" => score}} when is_integer(score) ->
        score >= 650

      %{"risk_indicators" => %{"buro_score" => score}} when is_integer(score) ->
        score >= 600

      _ ->
        true
    end
  end

  defp extract_provider_debt(%{"risk_indicators" => %{"existing_debt" => debt}})
       when is_binary(debt) do
    case Decimal.parse(debt) do
      {decimal, ""} -> decimal
      _ -> Decimal.new("0")
    end
  end

  defp extract_provider_debt(_), do: Decimal.new("0")
end
