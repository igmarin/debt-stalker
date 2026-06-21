defmodule DebtStalker.Workers.RiskEvaluationWorker do
  @moduledoc """
  Oban worker that evaluates risk for a credit application.

  Re-evaluates using country rules + provider summary, then moves the
  application through status transitions (submitted → pending_risk →
  approved/rejected/additional_review).

  Idempotent: if the application is not in a state that allows risk evaluation
  (already moved past pending_risk), the worker completes without side effects.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  alias DebtStalker.Applications
  alias DebtStalker.Countries.Registry

  @impl true
  def perform(%Oban.Job{args: %{"application_id" => app_id}}) do
    with {:ok, app} <- Applications.get_application(app_id),
         :ok <- ensure_evaluable(app) do
      evaluate_risk(app)
    else
      {:error, :not_found} -> :ok
      {:error, :not_evaluable} -> :ok
    end
  end

  defp ensure_evaluable(app) do
    if app.status in ["submitted", "pending_risk"] do
      :ok
    else
      {:error, :not_evaluable}
    end
  end

  defp evaluate_risk(app) do
    # First move to pending_risk if still in submitted
    app =
      if app.status == "submitted" do
        {:ok, updated} = Applications.update_status(app.id, "pending_risk", "risk_worker")
        updated
      else
        app
      end

    # Evaluate using country module
    {:ok, country_module} = Registry.lookup(app.country)

    financials_params = %{
      requested_amount: app.requested_amount,
      monthly_income: app.monthly_income,
      provider_debt: extract_provider_debt(app.provider_summary)
    }

    review_required = country_module.additional_review_required?(financials_params)

    # Determine final status
    new_status =
      cond do
        review_required -> "additional_review"
        risk_score_acceptable?(app) -> "approved"
        true -> "rejected"
      end

    Applications.update_status(app.id, new_status, "risk_worker")
    :ok
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
    Decimal.new(debt)
  end

  defp extract_provider_debt(_), do: Decimal.new("0")
end
