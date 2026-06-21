defmodule DebtStalker.DeadLetter.DeadLetterJob do
  @moduledoc """
  Schema for dead-letter jobs — exhausted Oban jobs captured for inspection.
  """

  use Ecto.Schema

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

    timestamps()
  end
end
