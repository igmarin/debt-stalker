defmodule DebtStalker.Repo.Migrations.AddUnprocessedApplicationEventsDepthIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:application_events, [:inserted_at],
             name: :application_events_unprocessed_inserted_at_idx,
             where: "processed_at IS NULL",
             concurrently: true
           )
  end

  def down do
    drop index(:application_events, [:inserted_at],
           name: :application_events_unprocessed_inserted_at_idx,
           concurrently: true
         )
  end
end
