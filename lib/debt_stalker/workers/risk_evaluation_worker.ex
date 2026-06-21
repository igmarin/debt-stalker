defmodule DebtStalker.Workers.RiskEvaluationWorker do
  @moduledoc """
  Oban worker that evaluates risk for a credit application.

  Delegates to `DebtStalker.Risk` context for business logic.
  Moves the application through status transitions:
  submitted → pending_risk → approved/rejected/additional_review.

  Idempotent: if the application is not in a state that allows risk evaluation
  (already moved past pending_risk), the worker completes without side effects.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  require Logger

  alias DebtStalker.Applications
  alias DebtStalker.Risk

  @doc "Evaluates risk for an application and transitions its status."
  @impl true
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
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
    with {:ok, app} <- maybe_transition_to_pending_risk(app),
         {:ok, new_status} <- Risk.evaluate(app),
         {:ok, _updated} <- Applications.update_status(app.id, new_status, "risk_worker") do
      Logger.info("Risk evaluation completed",
        application_id: app.id,
        country: app.country,
        status: new_status,
        worker: "RiskEvaluationWorker"
      )

      :ok
    else
      {:error, :invalid_transition} ->
        Logger.warning("Risk evaluation skipped: invalid transition",
          application_id: app.id,
          country: app.country,
          worker: "RiskEvaluationWorker"
        )

        :ok

      {:error, :unsupported_country} ->
        Logger.warning("Risk evaluation skipped: unsupported country",
          application_id: app.id,
          country: app.country,
          worker: "RiskEvaluationWorker"
        )

        :ok

      {:error, reason} ->
        Logger.error("Risk evaluation failed",
          application_id: app.id,
          country: app.country,
          worker: "RiskEvaluationWorker",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp maybe_transition_to_pending_risk(%{status: "submitted"} = app) do
    Applications.update_status(app.id, "pending_risk", "risk_worker")
  end

  defp maybe_transition_to_pending_risk(app), do: {:ok, app}
end
