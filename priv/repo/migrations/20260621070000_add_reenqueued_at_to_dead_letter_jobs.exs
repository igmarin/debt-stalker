defmodule DebtStalker.Repo.Migrations.AddReenqueuedAtToDeadLetterJobs do
  use Ecto.Migration

  def up do
    alter table(:dead_letter_jobs) do
      add :reenqueued_at, :utc_datetime
    end

    create index(:dead_letter_jobs, [:reenqueued_at])
  end

  def down do
    drop index(:dead_letter_jobs, [:reenqueued_at])

    alter table(:dead_letter_jobs) do
      remove :reenqueued_at
    end
  end
end
