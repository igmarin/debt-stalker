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
      captured_at: DateTime.utc_now()
    }

    # Idempotent: check if already captured
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
end
