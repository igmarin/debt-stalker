defmodule DebtStalker.Repo.Migrations.AddUnprocessedApplicationEventsDepthIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:application_events, [:inserted_at],
                           name: :application_events_unprocessed_inserted_at_idx,
                           where: "processed_at IS NULL",
                           concurrently: true
                         )

    drop_if_exists index(:application_events, [:processed_at, :inserted_at],
                     name: :application_events_processed_at_inserted_at_index,
                     concurrently: true
                   )
  end

  def down do
    drop_if_exists index(:application_events, [:inserted_at],
                     name: :application_events_unprocessed_inserted_at_idx,
                     concurrently: true
                   )

    create_if_not_exists index(:application_events, [:processed_at, :inserted_at],
                           name: :application_events_processed_at_inserted_at_index,
                           concurrently: true
                         )
  end
end
