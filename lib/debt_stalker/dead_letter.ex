defmodule DebtStalker.DeadLetter do
  @moduledoc """
  Dead-letter queue context for capturing exhausted Oban jobs.

  When an Oban job exhausts its retry budget, it is captured in the
  `dead_letter_jobs` table with the application_id, worker, redacted args,
  and last error for later inspection and potential re-enqueue.

  Capture is idempotent — the same job ID will not be captured twice.

  ## PII Redaction

  Job arguments are redacted before storage to prevent PII leakage.
  Sensitive keys (`identity_document`, `full_name`, `payload`) are masked
  or stripped. Only safe metadata (application_id, event_type, status,
  triggered_by) is preserved.
  """

  import Ecto.Query

  alias DebtStalker.DeadLetter.DeadLetterJob
  alias DebtStalker.Repo

  # String-keyed lists (Oban args are always string-keyed).
  # ~w/1 creates string lists by default — NOT atom lists.
  @sensitive_keys ~w(identity_document full_name payload document tax_id ssn)
  @safe_keys ~w(application_id event_type status triggered_by)

  @default_page_size 50
  @max_page_size 200

  @doc """
  Captures an exhausted Oban job in the dead-letter table.

  Idempotent — if a job with the same `job_id` already exists, returns
  the existing entry without creating a duplicate.

  Job arguments are redacted before storage — sensitive keys are masked
  to prevent PII leakage into the dead-letter table.

  ## Parameters

  - `job` — the `Oban.Job` struct that has exhausted its retries

  ## Returns

  - `{:ok, %DeadLetterJob{}}` on success
  - `{:error, changeset}` on validation failure
  """
  @spec capture(Oban.Job.t()) :: {:ok, DeadLetterJob.t()} | {:error, Ecto.Changeset.t()}
  def capture(%Oban.Job{} = job) do
    application_id = Map.get(job.args, "application_id")
    last_error = extract_last_error(job.errors)
    redacted_args = redact_args(job.args)

    attrs = %{
      job_id: job.id,
      application_id: application_id,
      worker: to_string(job.worker),
      queue: to_string(job.queue),
      args: redacted_args,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      last_error: last_error,
      captured_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    # Idempotent: check if already captured, then insert.
    # If a concurrent insert wins the race, the unique_constraint on job_id
    # triggers — we handle that by returning the existing entry.
    case Repo.get_by(DeadLetterJob, job_id: job.id) do
      nil ->
        %DeadLetterJob{}
        |> Ecto.Changeset.cast(attrs, [
          :job_id,
          :application_id,
          :worker,
          :queue,
          :args,
          :attempt,
          :max_attempts,
          :last_error,
          :captured_at
        ])
        |> Ecto.Changeset.validate_required([:job_id, :worker, :attempt, :max_attempts])
        |> Ecto.Changeset.unique_constraint(:job_id)
        |> Repo.insert()
        |> handle_race_condition(job.id)

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Lists dead-letter entries with cursor-based pagination.

  Returns entries ordered by most recent first. Pass `:before` with an
  entry ID to get the page before that entry, or `:limit` to control
  page size (default: 50, max: 200).

  ## Options

  - `:before` — entry ID cursor (returns entries with lower IDs)
  - `:limit` — page size (default: 50, max: 200)

  ## Returns

  A list of `%DeadLetterJob{}` structs.
  """
  @spec list(keyword()) :: [DeadLetterJob.t()]
  def list(opts \\ []) do
    limit = min(Keyword.get(opts, :limit, @default_page_size), @max_page_size)
    before_id = Keyword.get(opts, :before)

    query =
      from(d in DeadLetterJob,
        order_by: [desc: d.id],
        limit: ^limit
      )

    query =
      if before_id do
        from(d in query, where: d.id < ^before_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Returns the total count of dead-letter entries.

  ## Returns

  An integer count.
  """
  @spec count() :: non_neg_integer()
  def count do
    from(d in DeadLetterJob, select: count(d.id))
    |> Repo.one()
  end

  @doc """
  Retrieves a single dead-letter entry by ID.

  ## Parameters

  - `id` — the dead-letter entry ID

  ## Returns

  - `%DeadLetterJob{}` if found
  - `nil` if not found
  """
  @spec get(pos_integer()) :: DeadLetterJob.t() | nil
  def get(id) do
    Repo.get(DeadLetterJob, id)
  end

  @doc """
  Re-enqueues a dead-lettered job as a new Oban job.

  The new job is created with the same worker and safe args (PII-redacted).
  The dead-letter entry is marked with `reenqueued_at` to prevent duplicate
  re-enqueues. Workers are already idempotent, so replaying does not
  duplicate side effects.

  ## Parameters

  - `id` — the dead-letter entry ID

  ## Returns

  - `{:ok, %Oban.Job{}}` on success
  - `{:error, :not_found}` if the entry does not exist
  - `{:error, :already_reenqueued}` if the entry was already re-enqueued
  - `{:error, :unknown_worker}` if the worker module cannot be resolved
  """
  @spec reenqueue(pos_integer()) ::
          {:ok, Oban.Job.t()}
          | {:error, :not_found}
          | {:error, :already_reenqueued}
          | {:error, :unknown_worker}
  def reenqueue(id) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %DeadLetterJob{reenqueued_at: nil} = entry ->
        case resolve_worker(entry.worker) do
          {:ok, worker_module} ->
            {:ok, new_job} = insert_reenqueued_job(worker_module, entry)
            mark_reenqueued(entry)
            {:ok, new_job}

          {:error, :unknown_worker} ->
            {:error, :unknown_worker}
        end

      %DeadLetterJob{} ->
        {:error, :already_reenqueued}
    end
  end

  @doc """
  Re-enqueues all pending (not yet re-enqueued) dead-letter entries.

  Skips entries with unresolvable worker modules.

  ## Returns

  - `{:ok, count}` where count is the number of successfully re-enqueued jobs
  """
  @spec reenqueue_pending() :: {:ok, non_neg_integer()}
  def reenqueue_pending do
    pending =
      from(d in DeadLetterJob, where: is_nil(d.reenqueued_at))
      |> Repo.all()

    count =
      pending
      |> Enum.reduce(0, fn entry, acc ->
        case reenqueue(entry.id) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      end)

    {:ok, count}
  end

  # --- Private ---

  defp extract_last_error([]), do: nil

  defp extract_last_error(errors) when is_list(errors) do
    case List.last(errors) do
      %{"error" => error} -> error
      %{error: error} -> to_string(error)
      _ -> nil
    end
  end

  defp extract_last_error(_), do: nil

  @spec handle_race_condition({:ok, DeadLetterJob.t()} | {:error, Ecto.Changeset.t()}, integer()) ::
          {:ok, DeadLetterJob.t()} | {:error, Ecto.Changeset.t()}
  defp handle_race_condition({:ok, entry}, _job_id), do: {:ok, entry}

  defp handle_race_condition({:error, changeset}, job_id) do
    # If the unique_constraint on job_id triggered, a concurrent insert
    # won the race — return the existing entry.
    if errors_on(changeset, :job_id) != [] do
      {:ok, Repo.get_by!(DeadLetterJob, job_id: job_id)}
    else
      {:error, changeset}
    end
  end

  defp errors_on(changeset, field) do
    changeset.errors
    |> Enum.filter(fn {key, _} -> key == field end)
  end

  @spec redact_args(map()) :: map()
  defp redact_args(args) when is_map(args) do
    args
    |> Map.take(@safe_keys)
    |> Map.merge(redact_sensitive_keys(args))
  end

  defp redact_args(_args), do: %{}

  defp redact_sensitive_keys(args) do
    @sensitive_keys
    |> Enum.reduce(%{}, fn key, acc ->
      if Map.has_key?(args, key) do
        Map.put(acc, key, "[REDACTED]")
      else
        acc
      end
    end)
  end

  @spec resolve_worker(String.t()) :: {:ok, module()} | {:error, :unknown_worker}
  defp resolve_worker(worker_name) do
    module = Module.concat([worker_name])

    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :perform, 1) do
          {:ok, module}
        else
          {:error, :unknown_worker}
        end

      _ ->
        {:error, :unknown_worker}
    end
  end

  @spec insert_reenqueued_job(module(), DeadLetterJob.t()) :: {:ok, Oban.Job.t()}
  defp insert_reenqueued_job(worker_module, entry) do
    # Use the redacted args stored at capture time — safe metadata only.
    # Workers are idempotent, so replaying with these args won't duplicate
    # side effects even if the original job partially completed.
    %{application_id: entry.application_id}
    |> Map.merge(entry.args)
    |> worker_module.new(queue: String.to_atom(entry.queue || "events"))
    |> Oban.insert()
  end

  @spec mark_reenqueued(DeadLetterJob.t()) :: {:ok, DeadLetterJob.t()}
  defp mark_reenqueued(entry) do
    entry
    |> Ecto.Changeset.change(reenqueued_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end
end
