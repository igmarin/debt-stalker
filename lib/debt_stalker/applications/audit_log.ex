defmodule DebtStalker.Applications.AuditLog do
  @moduledoc """
  Schema for audit log entries.
  Append-only trail recording all significant actions on applications.
  """
  use Ecto.Schema

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
end
