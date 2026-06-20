defmodule DebtStalker.Workers.EventDispatcherWorker do
  @moduledoc """
  Oban worker that drains the application_events outbox.

  Claims unprocessed events using FOR UPDATE SKIP LOCKED (parallel-safe),
  marks them processed, and enqueues specialized workers based on event_type.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

  @batch_size 50

  @impl true
  def perform(_job) do
    claim_and_dispatch()
    :ok
  end

  defp claim_and_dispatch do
    {:ok, %{rows: events}} =
      SQL.query(
        Repo,
        """
        UPDATE application_events
        SET processed_at = NOW()
        WHERE id IN (
          SELECT id FROM application_events
          WHERE processed_at IS NULL
          ORDER BY inserted_at ASC
          FOR UPDATE SKIP LOCKED
          LIMIT $1
        )
        RETURNING id, application_id, event_type, payload
        """,
        [@batch_size]
      )

    Enum.each(events, &dispatch_event/1)
  end

  defp dispatch_event([_id, application_id, event_type, payload]) do
    app_id = encode_uuid(application_id)

    case event_type do
      "application.created" ->
        %{application_id: app_id, event_type: event_type, payload: payload}
        |> DebtStalker.Workers.RiskEvaluationWorker.new()
        |> Oban.insert()

      "application.status_changed" ->
        to_status = get_in(payload, ["to_status"])

        if to_status in ["approved", "rejected"] do
          %{application_id: app_id, event_type: event_type, payload: payload}
          |> DebtStalker.Workers.ExternalNotificationWorker.new()
          |> Oban.insert()
        end

      _ ->
        :ok
    end
  end

  defp encode_uuid(<<_::128>> = binary) do
    Ecto.UUID.cast!(binary)
  end

  defp encode_uuid(uuid) when is_binary(uuid), do: uuid
end
