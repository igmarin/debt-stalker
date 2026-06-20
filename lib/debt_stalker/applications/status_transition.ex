defmodule DebtStalker.Applications.StatusTransition do
  @moduledoc """
  Schema for application status transitions.
  Records every valid status change with from/to and who triggered it.
  """
  use Ecto.Schema

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
end
