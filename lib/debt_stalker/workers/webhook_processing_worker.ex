defmodule DebtStalker.Workers.WebhookProcessingWorker do
  @moduledoc """
  Oban worker that processes verified webhook events.

  Applies the status transition specified in the webhook payload and
  marks the corresponding webhook_events row as processed.

  Return behavior:
  - `:ok` on a successful transition.
  - `{:cancel, :not_found}` when the referenced application does not exist.
    This is a permanent failure; Oban should not retry because the
    application will never appear.
  - `:ok` on `{:error, :invalid_transition}` after marking the webhook event
    processed. The transition is invalid for the current application state,
    but retrying will never succeed, so we treat it as handled and do not
    requeue the job.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  require Logger

  alias DebtStalker.Applications
  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

  @impl true
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, :not_found}
  def perform(%Oban.Job{
        args: %{"application_id" => app_id, "status" => status, "triggered_by" => triggered_by}
      }) do
    case Applications.update_status(app_id, status, triggered_by) do
      {:ok, _app} ->
        mark_webhook_processed(app_id)
        :ok

      {:error, :not_found} ->
        Logger.warning("Webhook processing skipped: not_found",
          application_id: app_id,
          status: status,
          worker: "WebhookProcessingWorker",
          reason: "not_found"
        )

        {:cancel, :not_found}

      {:error, :invalid_transition} ->
        Logger.warning("Webhook processing skipped: invalid_transition",
          application_id: app_id,
          status: status,
          worker: "WebhookProcessingWorker",
          reason: "invalid_transition"
        )

        mark_webhook_processed(app_id)
        :ok
    end
  end

  # Marks all unprocessed webhook_events for the given application as processed.
  @spec mark_webhook_processed(Ecto.UUID.t()) :: :ok
  defp mark_webhook_processed(app_id) do
    {:ok, uuid_binary} = Ecto.UUID.dump(app_id)

    {:ok, _} =
      SQL.query(
        Repo,
        "UPDATE webhook_events SET processed = true WHERE application_id = $1 AND processed = false",
        [uuid_binary]
      )

    Logger.info("Webhook event marked processed",
      application_id: app_id,
      worker: "WebhookProcessingWorker"
    )

    :ok
  end
end
