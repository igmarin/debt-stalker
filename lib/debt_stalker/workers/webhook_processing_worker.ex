defmodule DebtStalker.Workers.WebhookProcessingWorker do
  @moduledoc """
  Oban worker that processes verified webhook events.

  Applies the status transition specified in the webhook payload.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  alias DebtStalker.Applications

  @impl true
  def perform(%Oban.Job{args: %{"application_id" => app_id, "status" => status, "triggered_by" => triggered_by}}) do
    case Applications.update_status(app_id, status, triggered_by) do
      {:ok, _app} -> :ok
      {:error, :not_found} -> :ok
      {:error, :invalid_transition} -> :ok
    end
  end
end
