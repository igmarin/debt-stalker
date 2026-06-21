defmodule DebtStalker.Workers.EventDispatcherWorker do
  @moduledoc """
  Oban worker that drains the application_events outbox.

  Claims unprocessed events using FOR UPDATE SKIP LOCKED (parallel-safe),
  dispatches each to specialized workers, then marks them processed
  individually — ensuring failed dispatches remain unprocessed for retry.
  """
  use Oban.Worker, queue: :events, max_attempts: 3

  require Logger

  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

  @batch_size 50

  @doc "Drains the application events outbox and dispatches events to workers."
  @impl true
  @spec perform(Oban.Job.t()) :: :ok
  def perform(_job) do
    {:ok, _count} = claim_and_dispatch()
    :ok
  end

  @doc """
  Claims and dispatches unprocessed events from the outbox.

  Returns `{:ok, count}` where count is the number of events successfully
  processed. Uses FOR UPDATE SKIP LOCKED for concurrent-safe consumption.

  Events are only marked processed AFTER successful dispatch — if dispatch
  fails, the event remains unprocessed and will be retried on the next run.
  """
  @spec claim_and_dispatch() :: {:ok, non_neg_integer()}
  def claim_and_dispatch do
    {:ok, %{rows: events}} =
      SQL.query(
        Repo,
        """
        SELECT id, application_id, event_type, payload
        FROM application_events
        WHERE processed_at IS NULL
        ORDER BY inserted_at ASC
        LIMIT $1
        FOR UPDATE SKIP LOCKED
        """,
        [@batch_size]
      )

    processed_count =
      events
      |> Enum.map(fn event ->
        case dispatch_event(event) do
          :ok ->
            mark_processed(event)
            1

          {:error, reason} ->
            [_id, _app_id, event_type, _payload] = event

            Logger.error("Event dispatch failed",
              worker: "EventDispatcherWorker",
              event_type: event_type,
              reason: inspect(reason)
            )

            0
        end
      end)
      |> Enum.sum()

    Logger.info("EventDispatcher processed events",
      worker: "EventDispatcherWorker",
      event_count: processed_count
    )

    {:ok, processed_count}
  end

  defp dispatch_event([_id, application_id, event_type, payload]) do
    app_id = encode_uuid(application_id)

    result =
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
          else
            {:ok, nil}
          end

        _ ->
          {:ok, nil}
      end

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_processed([id, _application_id, _event_type, _payload]) do
    {:ok, _} =
      SQL.query(
        Repo,
        "UPDATE application_events SET processed_at = NOW() WHERE id = $1",
        [id]
      )

    :ok
  end

  defp encode_uuid(<<_::128>> = binary) do
    Ecto.UUID.cast!(binary)
  end

  defp encode_uuid(uuid) when is_binary(uuid), do: uuid
end
