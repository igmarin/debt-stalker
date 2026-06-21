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
  - `"additional_review"` — country thresholds exceeded, or the country
    module does not implement `acceptable_risk_score?/1` (fail-safe)
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

      score_acceptable = acceptable_risk_score?(country_module, app.provider_summary)

      new_status =
        cond do
          review_required -> "additional_review"
          score_acceptable == true -> "approved"
          score_acceptable == false -> "rejected"
          true -> "additional_review"
        end

      {:ok, new_status}
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

  # Handles the optional acceptable_risk_score?/1 callback.
  # Countries that implement it (ES, MX) delegate to their logic.
  # Countries that don't implement it return :unknown, which routes
  # the application to additional_review (fail-safe: no automatic
  # approval or rejection without a score check).
  defp acceptable_risk_score?(country_module, provider_summary) do
    if function_exported?(country_module, :acceptable_risk_score?, 1) do
      country_module.acceptable_risk_score?(provider_summary)
    else
      :unknown
    end
  end
end
