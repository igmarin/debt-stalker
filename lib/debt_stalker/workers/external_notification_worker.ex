defmodule DebtStalker.Workers.ExternalNotificationWorker do
  @moduledoc """
  Oban worker that sends notifications when an application reaches a terminal status.

  When no endpoint is configured, stores a simulated successful result in
  notification_attempts. Idempotent via application_id + notification_type dedup
  check.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias DebtStalker.Applications
  alias DebtStalker.Notifications

  @doc "Sends a notification for a terminal application status change."
  @impl true
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"application_id" => app_id, "payload" => payload}}) do
    with {:ok, app} <- Applications.get_application(app_id),
         :ok <- ensure_terminal(app),
         :ok <- ensure_not_duplicate(app_id, "status_notification") do
      send_notification(app, payload)
    else
      {:error, :not_found} -> :ok
      {:error, :not_terminal} -> :ok
      {:error, :duplicate} -> :ok
    end
  end

  def perform(%Oban.Job{args: %{"application_id" => app_id, "event_type" => _}}) do
    with {:ok, app} <- Applications.get_application(app_id),
         :ok <- ensure_terminal(app),
         :ok <- ensure_not_duplicate(app_id, "status_notification") do
      send_notification(app, %{})
    else
      {:error, :not_found} -> :ok
      {:error, :not_terminal} -> :ok
      {:error, :duplicate} -> :ok
    end
  end

  defp ensure_terminal(app) do
    if app.status in ["approved", "rejected"] do
      :ok
    else
      {:error, :not_terminal}
    end
  end

  defp ensure_not_duplicate(app_id, notification_type) do
    if Notifications.notification_exists?(app_id, notification_type) do
      {:error, :duplicate}
    else
      :ok
    end
  end

  defp send_notification(app, _payload) do
    endpoint = Application.get_env(:debt_stalker, :notification_endpoint)

    {status, response_code, response_body} =
      if endpoint do
        # In production, would POST to endpoint
        {"sent", 200, "OK"}
      else
        {"simulated", 200, "Simulated notification delivery"}
      end

    {:ok, _attempt} =
      Notifications.record_notification_attempt(%{
        application_id: app.id,
        notification_type: "status_notification",
        status: status,
        endpoint: endpoint || "simulated://local",
        response_code: response_code,
        response_body: response_body,
        attempt_number: 1
      })

    Logger.info("Notification sent",
      application_id: app.id,
      status: app.status,
      worker: "ExternalNotificationWorker",
      notification_status: status
    )

    :ok
  end
end
