defmodule DebtStalker.Applications.AuditLog do
  @moduledoc """
  Schema for audit log entries.
  Append-only trail recording all significant actions on applications.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "audit_logs" do
    field :application_id, :binary_id
    field :action, :string
    field :actor, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  @type t :: %__MODULE__{
          application_id: binary() | nil,
          action: String.t() | nil,
          actor: String.t() | nil,
          metadata: map()
        }

  @doc """
  Creates a changeset for an audit log entry.

  Validates that all required fields are present so that invalid
  audit records are rejected at the changeset level.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = struct, attrs) do
    struct
    |> cast(attrs, [:application_id, :action, :actor, :metadata])
    |> validate_required([:application_id, :action, :actor])
  end
end
