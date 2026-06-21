defmodule DebtStalker.Workers.WebhookProcessingWorker do
  @moduledoc """
  Oban worker that processes verified webhook events.

  Applies the status transition specified in the webhook payload and
  marks the corresponding webhook_events row as processed.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  require Logger

  alias DebtStalker.Applications
  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

  @impl true
  def perform(%Oban.Job{
        args: %{"application_id" => app_id, "status" => status, "triggered_by" => triggered_by}
      }) do
    case Applications.update_status(app_id, status, triggered_by) do
      {:ok, _app} ->
        mark_webhook_processed(app_id)
        :ok

      {:error, :not_found} ->
        :ok

      {:error, :invalid_transition} ->
        :ok
    end
  end

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
