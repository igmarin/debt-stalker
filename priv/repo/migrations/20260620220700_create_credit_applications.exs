defmodule DebtStalker.Repo.Migrations.CreateCreditApplications do
  use Ecto.Migration

  def change do
    create table(:credit_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :country, :string, null: false
      add :full_name, :string, null: false
      add :identity_document, :binary, null: false
      add :identity_document_hash, :string, null: false
      add :requested_amount, :decimal, null: false
      add :monthly_income, :decimal, null: false
      add :application_date, :utc_datetime_usec, null: false
      add :status, :string, null: false, default: "submitted"
      add :additional_review_required, :boolean, null: false, default: false
      add :provider_summary, :map
      add :risk_result, :map

      timestamps(type: :utc_datetime_usec)
    end

    # Composite index for listing queries: filter by country + status + date
    create index(:credit_applications, [:country, :status, :application_date])

    # Index for date-range queries and cursor pagination
    create index(:credit_applications, [:application_date])

    # Index for document dedup/lookup via hash
    create index(:credit_applications, [:identity_document_hash])
  end
end
