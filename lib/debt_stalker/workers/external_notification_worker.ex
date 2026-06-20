defmodule DebtStalker.Workers.ExternalNotificationWorker do
  @moduledoc """
  Oban worker that sends notifications when an application reaches a terminal status.

  When no endpoint is configured, stores a simulated successful result.
  Idempotent: rerun does not duplicate notifications.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  @impl true
  def perform(_job) do
    # Stub — full implementation in T5.3
    :ok
  end
end
