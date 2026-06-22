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
  alias DebtStalker.Telemetry
  alias Ecto.Adapters.SQL

  @default_batch_size 50
  @default_max_batches_per_run 5

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
    %{batch_size: batch_size, max_batches_per_run: max_batches_per_run} = dispatcher_config()

    measurements =
      batch_size
      |> drain_batches(max_batches_per_run, empty_dispatch_stats())
      |> Map.merge(outbox_depth())

    Telemetry.emit_outbox_dispatch(measurements)

    Logger.info("EventDispatcher processed events",
      worker: "EventDispatcherWorker",
      application_id: "system",
      event_id: "outbox_dispatch",
      country: "system",
      status: "completed",
      event_count: measurements.processed_count,
      failed_count: measurements.failed_count,
      claimed_count: measurements.claimed_count,
      batch_count: measurements.batch_count,
      remaining_count: measurements.remaining_count,
      oldest_unprocessed_age_ms: measurements.oldest_unprocessed_age_ms
    )

    {:ok, measurements.processed_count}
  end

  defp drain_batches(_batch_size, 0, stats), do: stats

  defp drain_batches(batch_size, batches_remaining, stats) do
    batch_stats = claim_and_dispatch_batch(batch_size)
    stats = merge_dispatch_stats(stats, batch_stats)

    # Stop draining once the outbox is empty or the last claimed batch was not full.
    cond do
      batch_stats.claimed_count == 0 ->
        stats

      batch_stats.claimed_count < batch_size ->
        stats

      true ->
        drain_batches(batch_size, batches_remaining - 1, stats)
    end
  end

  defp claim_and_dispatch_batch(batch_size) do
    case Repo.transaction(fn ->
           events = claim_events(batch_size)
           dispatch_events(events)
         end) do
      {:ok, stats} ->
        stats

      {:error, reason} ->
        safe_reason = sanitized_reason(reason)

        Logger.error("EventDispatcher batch transaction failed",
          worker: "EventDispatcherWorker",
          application_id: "system",
          event_id: "outbox_dispatch",
          country: "system",
          status: "failed",
          reason: safe_reason
        )

        raise "Event dispatcher batch transaction failed: #{safe_reason}"
    end
  end

  defp claim_events(batch_size) do
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
        [batch_size]
      )

    events
  end

  defp dispatch_events(events) do
    events
    |> Enum.reduce(empty_dispatch_stats(), fn event, stats ->
      case dispatch_event(event) do
        :ok ->
          mark_processed(event)
          %{stats | processed_count: stats.processed_count + 1}

        {:error, reason} ->
          log_dispatch_failure(event, reason)
          %{stats | failed_count: stats.failed_count + 1}
      end
    end)
    |> Map.put(:claimed_count, length(events))
    |> Map.put(:batch_count, batch_count(events))
  end

  defp log_dispatch_failure([event_id, application_id, event_type, payload], reason) do
    Logger.error("Event dispatch failed",
      worker: "EventDispatcherWorker",
      application_id: encode_uuid(application_id),
      event_id: encode_uuid(event_id),
      country: Map.get(payload, "country", "unknown"),
      status: Map.get(payload, "to_status", "failed"),
      event_type: event_type,
      reason: sanitized_reason(reason)
    )
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

  defp outbox_depth do
    {:ok, %{rows: [[remaining_count, oldest_unprocessed_age_ms]]}} =
      SQL.query(
        Repo,
        """
        SELECT
          COUNT(*),
          COALESCE((EXTRACT(EPOCH FROM (NOW() - MIN(inserted_at))) * 1000)::bigint, 0)
        FROM application_events
        WHERE processed_at IS NULL
        """,
        []
      )

    %{
      remaining_count: remaining_count,
      oldest_unprocessed_age_ms: oldest_unprocessed_age_ms
    }
  end

  defp dispatcher_config do
    config = Application.get_env(:debt_stalker, :event_dispatcher, [])

    %{
      batch_size:
        config
        |> Keyword.get(:batch_size, @default_batch_size)
        |> positive_integer_or_default(@default_batch_size),
      max_batches_per_run:
        config
        |> Keyword.get(:max_batches_per_run, @default_max_batches_per_run)
        |> positive_integer_or_default(@default_max_batches_per_run)
    }
  end

  defp positive_integer_or_default(value, _default) when is_integer(value) and value > 0,
    do: value

  defp positive_integer_or_default(_value, default), do: default

  defp empty_dispatch_stats do
    %{
      processed_count: 0,
      failed_count: 0,
      claimed_count: 0,
      batch_count: 0
    }
  end

  defp merge_dispatch_stats(left, right) do
    %{
      processed_count: left.processed_count + right.processed_count,
      failed_count: left.failed_count + right.failed_count,
      claimed_count: left.claimed_count + right.claimed_count,
      batch_count: left.batch_count + right.batch_count
    }
  end

  defp batch_count([]), do: 0
  defp batch_count(_events), do: 1

  defp sanitized_reason(%Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    inspect(%{action: changeset.action, errors: errors, valid?: changeset.valid?})
  end

  defp sanitized_reason(reason), do: inspect(reason, limit: 50)

  defp encode_uuid(<<_::128>> = binary) do
    Ecto.UUID.cast!(binary)
  end

  defp encode_uuid(uuid) when is_binary(uuid), do: uuid
end
