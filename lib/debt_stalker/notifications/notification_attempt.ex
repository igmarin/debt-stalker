defmodule DebtStalker.Notifications.NotificationAttempt do
  @moduledoc """
  Ecto schema for outbound notification attempts.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias DebtStalker.Applications.CreditApplication

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          application_id: Ecto.UUID.t() | nil,
          application: CreditApplication.t() | Ecto.Association.NotLoaded.t() | nil,
          notification_type: String.t() | nil,
          status: String.t() | nil,
          endpoint: String.t() | nil,
          response_code: integer() | nil,
          response_body: String.t() | nil,
          attempt_number: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notification_attempts" do
    belongs_to :application, CreditApplication

    field :notification_type, :string
    field :status, :string, default: "pending"
    field :endpoint, :string
    field :response_code, :integer
    field :response_body, :string
    field :attempt_number, :integer, default: 1

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Builds a changeset for a new notification attempt.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = attempt, attrs) do
    attempt
    |> cast(attrs, [
      :application_id,
      :notification_type,
      :status,
      :endpoint,
      :response_code,
      :response_body,
      :attempt_number
    ])
    |> validate_required([:application_id, :notification_type, :status, :attempt_number])
  end
end
