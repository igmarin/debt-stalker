defmodule DebtStalker.DeadLetter.DeadLetterJob do
  @moduledoc """
  Schema for dead-letter jobs — exhausted Oban jobs captured for inspection.
  """

  use Ecto.Schema

  @typedoc """
  A dead-letter job — an exhausted Oban job captured for inspection
  and potential re-enqueue.

  ## Fields

  - `job_id` — the original Oban job ID
  - `application_id` — the associated application (if any)
  - `worker` — the worker module name as a string
  - `queue` — the original queue name
  - `args` — PII-redacted job arguments (safe metadata only)
  - `attempt` — the attempt number when the job exhausted
  - `max_attempts` — the configured max retry attempts
  - `last_error` — the last error message from the job's error list
  - `captured_at` — when the job was captured into the DLQ
  - `reenqueued_at` — when the job was re-enqueued (nil if not yet re-enqueued)
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          job_id: integer(),
          application_id: String.t() | nil,
          worker: String.t(),
          queue: String.t() | nil,
          args: map(),
          attempt: integer(),
          max_attempts: integer(),
          last_error: String.t() | nil,
          captured_at: DateTime.t(),
          reenqueued_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "dead_letter_jobs" do
    field :job_id, :integer
    field :application_id, :string
    field :worker, :string
    field :queue, :string
    field :args, :map, default: %{}
    field :attempt, :integer
    field :max_attempts, :integer
    field :last_error, :string
    field :captured_at, :utc_datetime
    field :reenqueued_at, :utc_datetime

    timestamps()
  end
end
