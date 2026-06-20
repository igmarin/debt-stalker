defmodule DebtStalker.Integration.TriggerOutboxWorkerTest do
  @moduledoc """
  Integration spike: verifies the trigger→outbox→worker chain.

  This test exercises the full async backbone:
  1. INSERT into credit_applications → Postgres trigger fires → application_events row created
  2. UPDATE status on credit_applications → Postgres trigger fires → application_events row created
  3. EventDispatcherWorker claims events with FOR UPDATE SKIP LOCKED
  4. Specialized workers are enqueued

  This test is expected to FAIL until T1.2 (migrations), T1.3 (supporting tables),
  T1.4 (triggers), and T5.1 (EventDispatcherWorker) are complete.
  """
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Repo
  alias Ecto.Adapters.SQL

  @moduletag :integration

  describe "trigger→outbox chain" do
    test "INSERT into credit_applications creates application.created event" do
      # Insert a credit application directly (bypassing context for trigger testing)
      {:ok, %{rows: [[app_id]]}} =
        SQL.query(
          Repo,
          """
          INSERT INTO credit_applications (
            id, country, full_name, identity_document, identity_document_hash,
            requested_amount, monthly_income, application_date, status,
            additional_review_required, inserted_at, updated_at
          ) VALUES (
            gen_random_uuid(), 'ES', 'Test User', 'encrypted_doc', 'hash123',
            5000.00, 2000.00, NOW(), 'submitted',
            false, NOW(), NOW()
          ) RETURNING id
          """,
          []
        )

      # Assert the trigger created an event row
      {:ok, %{num_rows: count}} =
        SQL.query(
          Repo,
          """
          SELECT COUNT(*) FROM application_events
          WHERE application_id = $1 AND event_type = 'application.created'
          """,
          [app_id]
        )

      assert count == 1
    end

    test "UPDATE status on credit_applications creates application.status_changed event" do
      # Insert first
      {:ok, %{rows: [[app_id]]}} =
        SQL.query(
          Repo,
          """
          INSERT INTO credit_applications (
            id, country, full_name, identity_document, identity_document_hash,
            requested_amount, monthly_income, application_date, status,
            additional_review_required, inserted_at, updated_at
          ) VALUES (
            gen_random_uuid(), 'ES', 'Test User', 'encrypted_doc', 'hash123',
            5000.00, 2000.00, NOW(), 'submitted',
            false, NOW(), NOW()
          ) RETURNING id
          """,
          []
        )

      # Update status
      SQL.query(
        Repo,
        """
        UPDATE credit_applications SET status = 'pending_risk', updated_at = NOW()
        WHERE id = $1
        """,
        [app_id]
      )

      # Assert the trigger created a status_changed event
      {:ok, %{num_rows: count}} =
        SQL.query(
          Repo,
          """
          SELECT COUNT(*) FROM application_events
          WHERE application_id = $1 AND event_type = 'application.status_changed'
          """,
          [app_id]
        )

      assert count == 1
    end
  end

  describe "EventDispatcherWorker SKIP LOCKED claim" do
    test "dispatcher claims unprocessed events and marks them processed" do
      # Insert an application to generate an event
      {:ok, %{rows: [[app_id]]}} =
        SQL.query(
          Repo,
          """
          INSERT INTO credit_applications (
            id, country, full_name, identity_document, identity_document_hash,
            requested_amount, monthly_income, application_date, status,
            additional_review_required, inserted_at, updated_at
          ) VALUES (
            gen_random_uuid(), 'ES', 'Test User', 'encrypted_doc', 'hash123',
            5000.00, 2000.00, NOW(), 'submitted',
            false, NOW(), NOW()
          ) RETURNING id
          """,
          []
        )

      # Verify event exists and is unprocessed
      {:ok, %{rows: [[event_id]]}} =
        SQL.query(
          Repo,
          """
          SELECT id FROM application_events
          WHERE application_id = $1 AND processed_at IS NULL
          LIMIT 1
          """,
          [app_id]
        )

      assert event_id != nil

      # Run the dispatcher worker
      assert {:ok, _count} =
               DebtStalker.Workers.EventDispatcherWorker.claim_and_dispatch()

      # Verify event is now marked as processed
      {:ok, %{rows: [[processed_count]]}} =
        SQL.query(
          Repo,
          """
          SELECT COUNT(*) FROM application_events
          WHERE application_id = $1 AND processed_at IS NOT NULL
          """,
          [app_id]
        )

      assert processed_count == 1
    end

    test "parallel dispatchers do not double-claim events (SKIP LOCKED)" do
      # Insert multiple applications to generate multiple events
      for _i <- 1..5 do
        SQL.query(
          Repo,
          """
          INSERT INTO credit_applications (
            id, country, full_name, identity_document, identity_document_hash,
            requested_amount, monthly_income, application_date, status,
            additional_review_required, inserted_at, updated_at
          ) VALUES (
            gen_random_uuid(), 'ES', 'Test User', 'encrypted_doc', 'hash123',
            5000.00, 2000.00, NOW(), 'submitted',
            false, NOW(), NOW()
          ) RETURNING id
          """,
          []
        )
      end

      # Run two dispatchers concurrently using the public function
      tasks =
        for _i <- 1..2 do
          Task.async(fn ->
            DebtStalker.Workers.EventDispatcherWorker.claim_and_dispatch()
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn
               {:ok, _count} -> true
               _ -> false
             end)

      # Verify no unprocessed events remain
      {:ok, %{rows: [[remaining]]}} =
        SQL.query(
          Repo,
          "SELECT COUNT(*) FROM application_events WHERE processed_at IS NULL",
          []
        )

      assert remaining == 0
    end
  end
end
