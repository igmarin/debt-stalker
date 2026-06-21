defmodule DebtStalker.Repo.Migrations.AddReenqueuedAtToDeadLetterJobs do
  use Ecto.Migration

  def change do
    alter table(:dead_letter_jobs) do
      add :reenqueued_at, :utc_datetime
    end

    create index(:dead_letter_jobs, [:reenqueued_at])
  end
end
