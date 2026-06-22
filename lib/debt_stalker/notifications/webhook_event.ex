defmodule DebtStalker.Notifications.WebhookEvent do
  @moduledoc """
  Ecto schema for inbound provider webhook events.

  Only metadata (source, payload hash, verification status) is stored — never
  the raw provider payload.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias DebtStalker.Applications.CreditApplication

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          application_id: Ecto.UUID.t() | nil,
          application: CreditApplication.t() | Ecto.Association.NotLoaded.t() | nil,
          source: String.t() | nil,
          payload_hash: String.t() | nil,
          verified: boolean() | nil,
          processed: boolean() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_events" do
    belongs_to :application, CreditApplication

    field :source, :string
    field :payload_hash, :string
    field :verified, :boolean, default: false
    field :processed, :boolean, default: false

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Builds a changeset for a new webhook event.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = event, attrs) do
    event
    |> cast(attrs, [
      :application_id,
      :source,
      :payload_hash,
      :verified,
      :processed
    ])
    |> validate_required([:application_id, :source, :payload_hash, :verified, :processed])
  end
end
