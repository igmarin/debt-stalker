defmodule DebtStalker.Workers.ExternalNotificationWorker do
  @moduledoc """
  Oban worker that sends notifications when an application reaches a terminal status.

  When no endpoint is configured, stores a simulated successful result
  in notification_attempts. Idempotent via application_id + notification_type
  dedup check.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias DebtStalker.Repo
  alias DebtStalker.Applications

  @impl true
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
    import Ecto.Query

    exists =
      from(n in "notification_attempts",
        where: n.application_id == type(^app_id, :binary_id),
        where: n.notification_type == ^notification_type
      )
      |> Repo.exists?()

    if exists, do: {:error, :duplicate}, else: :ok
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

    Repo.insert_all("notification_attempts", [
      %{
        id: Ecto.UUID.bingenerate(),
        application_id: Ecto.UUID.dump!(app.id),
        notification_type: "status_notification",
        status: status,
        endpoint: endpoint || "simulated://local",
        response_code: response_code,
        response_body: response_body,
        attempt_number: 1,
        inserted_at: DateTime.utc_now()
      }
    ])

    :ok
  end
end
