defmodule DebtStalker.Repo.Migrations.CreateSupportingTables do
  use Ecto.Migration

  def change do
    # application_status_transitions — records every valid status change
    create table(:application_status_transitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :restrict),
          null: false

      add :from_status, :string, null: false
      add :to_status, :string, null: false
      add :reason, :string
      add :triggered_by, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:application_status_transitions, [:application_id])

    # application_events — outbox for trigger-generated async events
    create table(:application_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :restrict),
          null: false

      add :event_type, :string, null: false
      add :payload, :map, default: %{}
      add :processed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:application_events, [:application_id])
    create index(:application_events, [:processed_at, :inserted_at])

    # audit_logs — append-only audit trail
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :restrict),
          null: false

      add :action, :string, null: false
      add :actor, :string, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_logs, [:application_id])

    # webhook_events — inbound webhook tracking
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :restrict),
          null: false

      add :source, :string, null: false
      add :payload_hash, :string, null: false
      add :verified, :boolean, null: false, default: false
      add :processed, :boolean, null: false, default: false
      add :raw_payload, :map

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:webhook_events, [:application_id])
    create unique_index(:webhook_events, [:payload_hash])

    # notification_attempts — outbound notification tracking
    create table(:notification_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id,
          references(:credit_applications, type: :binary_id, on_delete: :restrict),
          null: false

      add :notification_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :endpoint, :string
      add :response_code, :integer
      add :response_body, :text
      add :attempt_number, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:notification_attempts, [:application_id])
  end
end
