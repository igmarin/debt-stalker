defmodule DebtStalker.Repo.Migrations.CreateDeadLetterJobs do
  use Ecto.Migration

  def change do
    create table(:dead_letter_jobs) do
      add :job_id, :integer, null: false
      add :application_id, :string
      add :worker, :string, null: false
      add :queue, :string
      add :args, :map, null: false, default: %{}
      add :attempt, :integer, null: false
      add :max_attempts, :integer, null: false
      add :last_error, :text
      add :captured_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps()
    end

    create unique_index(:dead_letter_jobs, [:job_id])
    create index(:dead_letter_jobs, [:application_id])
    create index(:dead_letter_jobs, [:worker])
    create index(:dead_letter_jobs, [:inserted_at])
  end
end
