defmodule DebtStalker.Repo.Migrations.RemoveRawPayloadFromWebhookEvents do
  use Ecto.Migration

  def up do
    alter table(:webhook_events) do
      remove :raw_payload
    end
  end

  def down do
    alter table(:webhook_events) do
      add :raw_payload, :map
    end
  end
end
