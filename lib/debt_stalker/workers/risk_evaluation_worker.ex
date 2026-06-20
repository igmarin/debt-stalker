defmodule DebtStalker.Workers.RiskEvaluationWorker do
  @moduledoc """
  Oban worker that evaluates risk for a credit application.

  Re-evaluates using country rules + provider summary, then moves the
  application through status transitions (pending_risk → approved/rejected/additional_review).
  Idempotent: rerun does not double-transition.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  @impl true
  def perform(_job) do
    # Stub — full implementation in T5.2
    :ok
  end
end
