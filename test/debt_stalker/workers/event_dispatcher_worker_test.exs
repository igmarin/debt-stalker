defmodule DebtStalker.Workers.EventDispatcherWorkerTest do
  use DebtStalker.DataCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  alias DebtStalker.Workers.EventDispatcherWorker
  alias Ecto.Adapters.SQL

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "perform/1" do
    test "claims unprocessed events and marks them processed" do
      # Create an application (trigger generates application.created event)
      {:ok, app} = DebtStalker.Applications.create_application(@valid_es_attrs)
      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      # Verify unprocessed event exists
      {:ok, %{rows: [[count]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM application_events WHERE application_id = $1 AND processed_at IS NULL",
          [uuid_binary]
        )

      assert count >= 1

      # Run the dispatcher
      assert :ok = perform_job(EventDispatcherWorker, %{})

      # Verify event is now processed
      {:ok, %{rows: [[processed_count]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM application_events WHERE application_id = $1 AND processed_at IS NOT NULL",
          [uuid_binary]
        )

      assert processed_count >= 1
    end

    test "enqueues RiskEvaluationWorker for application.created events" do
      {:ok, _app} = DebtStalker.Applications.create_application(@valid_es_attrs)

      perform_job(EventDispatcherWorker, %{})

      assert_enqueued(worker: DebtStalker.Workers.RiskEvaluationWorker)
    end

    test "enqueues ExternalNotificationWorker for status_changed to approved" do
      {:ok, app} = DebtStalker.Applications.create_application(@valid_es_attrs)

      # Move to pending_risk then approved (generates status_changed events)
      {:ok, _} = DebtStalker.Applications.update_status(app.id, "pending_risk", "system")

      # First dispatch to clear the created event
      perform_job(EventDispatcherWorker, %{})

      {:ok, _} = DebtStalker.Applications.update_status(app.id, "approved", "system")

      # Dispatch the status_changed event
      perform_job(EventDispatcherWorker, %{})

      assert_enqueued(worker: DebtStalker.Workers.ExternalNotificationWorker)
    end

    test "does not double-process events on multiple runs" do
      {:ok, _app} = DebtStalker.Applications.create_application(@valid_es_attrs)

      perform_job(EventDispatcherWorker, %{})
      perform_job(EventDispatcherWorker, %{})

      # Should only have 1 RiskEvaluation job, not 2
      jobs = all_enqueued(worker: DebtStalker.Workers.RiskEvaluationWorker)
      assert length(jobs) == 1
    end
  end
end
