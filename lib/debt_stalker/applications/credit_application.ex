defmodule DebtStalker.Applications.CreditApplication do
  @moduledoc """
  Schema for credit applications.

  `identity_document` is encrypted at rest via Cloak. The `identity_document_hash`
  field is a SHA-256 hash used for lookup/dedup without decryption.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias DebtStalker.Countries.Registry

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @valid_statuses ~w(submitted pending_risk additional_review approved rejected provider_error cancelled)

  schema "credit_applications" do
    field :country, :string
    field :full_name, :string
    field :identity_document, DebtStalker.Vault.EncryptedBinary
    field :identity_document_hash, :string
    field :requested_amount, :decimal
    field :monthly_income, :decimal
    field :application_date, :utc_datetime_usec
    field :status, :string, default: "submitted"
    field :additional_review_required, :boolean, default: false
    field :provider_summary, :map
    field :risk_result, :map

    timestamps()
  end

  @typedoc "A credit application record."
  @type t :: %__MODULE__{}

  @required_fields ~w(country full_name identity_document requested_amount monthly_income)a
  @optional_fields ~w(status additional_review_required provider_summary risk_result application_date identity_document_hash)a

  @doc "Returns a changeset for creating or updating a credit application."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(application, attrs) do
    application
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_country()
    |> validate_number(:requested_amount, greater_than: 0)
    |> validate_number(:monthly_income, greater_than: 0)
    |> put_identity_document_hash()
    |> put_application_date()
  end

  defp put_identity_document_hash(changeset) do
    case get_change(changeset, :identity_document) do
      nil -> changeset
      document -> put_change(changeset, :identity_document_hash, hash_document(document))
    end
  end

  defp validate_country(changeset) do
    case get_field(changeset, :country) do
      nil ->
        changeset

      country ->
        if country in Registry.supported_countries() do
          changeset
        else
          add_error(changeset, :country, "is not supported")
        end
    end
  end

  defp put_application_date(changeset) do
    case get_field(changeset, :application_date) do
      nil -> put_change(changeset, :application_date, DateTime.utc_now())
      _ -> changeset
    end
  end

  @doc "Returns a SHA-256 hash of the identity document for deduplication."
  @spec hash_document(String.t()) :: String.t()
  def hash_document(document) do
    :crypto.hash(:sha256, document) |> Base.encode16(case: :lower)
  end

  @doc "Redacts an identity document to last-4 for display or responses."
  @spec redact_document(String.t() | nil) :: String.t()
  def redact_document(nil), do: "****"
  def redact_document(document) when byte_size(document) <= 4, do: "****"

  def redact_document(document) do
    last_four = String.slice(document, -4, 4)
    "****#{last_four}"
  end

  @doc "Returns the list of valid application statuses."
  @spec valid_statuses() :: [String.t()]
  def valid_statuses, do: @valid_statuses
end
