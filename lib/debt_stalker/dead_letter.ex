defmodule DebtStalker.DeadLetter do
  @moduledoc """
  Dead-letter queue context for capturing exhausted Oban jobs.

  When an Oban job exhausts its retry budget, it is captured in the
  `dead_letter_jobs` table with the application_id, worker, args, and
  last error for later inspection and potential re-enqueue.

  Capture is idempotent — the same job ID will not be captured twice.
  """

  import Ecto.Query

  alias DebtStalker.DeadLetter.DeadLetterJob
  alias DebtStalker.Repo

  @doc """
  Captures an exhausted Oban job in the dead-letter table.

  Idempotent — if a job with the same `job_id` already exists, returns
  the existing entry without creating a duplicate.

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

    attrs = %{
      job_id: job.id,
      application_id: application_id,
      worker: to_string(job.worker),
      queue: to_string(job.queue),
      args: job.args,
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
  Lists all dead-letter entries ordered by most recent first.

  ## Returns

  A list of `%DeadLetterJob{}` structs.
  """
  @spec list() :: [DeadLetterJob.t()]
  def list do
    from(d in DeadLetterJob, order_by: [desc: d.id])
    |> Repo.all()
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
end
