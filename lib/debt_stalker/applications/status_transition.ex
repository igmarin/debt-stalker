defmodule DebtStalker.Applications.StatusTransition do
  @moduledoc """
  Schema for application status transitions.
  Records every valid status change with from/to and who triggered it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "application_status_transitions" do
    field :application_id, :binary_id
    field :from_status, :string
    field :to_status, :string
    field :reason, :string
    field :triggered_by, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          application_id: binary() | nil,
          from_status: String.t() | nil,
          to_status: String.t() | nil,
          reason: String.t() | nil,
          triggered_by: String.t() | nil
        }

  @doc """
  Creates a changeset for a status transition.

  Validates that all required fields are present so that invalid
  transitions are rejected at the changeset level, not just at the
  database constraint level.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:application_id, :from_status, :to_status, :reason, :triggered_by])
    |> validate_required([:application_id, :from_status, :to_status, :triggered_by])
  end
end
