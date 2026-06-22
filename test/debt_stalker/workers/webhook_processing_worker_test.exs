defmodule DebtStalker.Workers.WebhookProcessingWorkerTest do
  @moduledoc false
  use DebtStalker.DataCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  import ExUnit.CaptureLog

  alias DebtStalker.Applications
  alias DebtStalker.Workers.WebhookProcessingWorker
  alias Ecto.Adapters.SQL

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "perform/1" do
    test "applies status transition from webhook payload" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      assert :ok =
               perform_job(WebhookProcessingWorker, %{
                 "application_id" => app.id,
                 "status" => "approved",
                 "triggered_by" => "webhook"
               })

      {:ok, updated} = Applications.get_application(app.id)
      assert updated.status == "approved"
    end

    test "marks webhook_event as processed after successful processing" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      # Insert a webhook_event row manually
      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, _} =
        SQL.query(
          DebtStalker.Repo,
          """
          INSERT INTO webhook_events (id, application_id, source, payload_hash, verified, processed, inserted_at)
          VALUES ($1, $2, 'provider_es', 'testhash123', true, false, NOW())
          """,
          [Ecto.UUID.bingenerate(), uuid_binary]
        )

      # Verify it's unprocessed
      {:ok, %{rows: [[before]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT processed FROM webhook_events WHERE application_id = $1",
          [uuid_binary]
        )

      assert before == false

      # Run the worker
      assert :ok =
               perform_job(WebhookProcessingWorker, %{
                 "application_id" => app.id,
                 "status" => "approved",
                 "triggered_by" => "webhook"
               })

      # Verify webhook_event is now marked processed
      {:ok, %{rows: [[processed_val]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT processed FROM webhook_events WHERE application_id = $1",
          [uuid_binary]
        )

      assert processed_val == true
    end

    test "non-existent application returns cancel and does not mark webhook processed" do
      fake_id = Ecto.UUID.generate()
      {:ok, uuid_binary} = Ecto.UUID.dump(fake_id)

      logs =
        capture_log(fn ->
          assert {:cancel, :not_found} =
                   perform_job(WebhookProcessingWorker, %{
                     "application_id" => fake_id,
                     "status" => "approved",
                     "triggered_by" => "webhook"
                   })
        end)

      assert logs =~ "Webhook processing skipped"
      assert logs =~ "not_found"

      # No webhook event should be marked processed for a missing application.
      # The FK prevents inserting one for a non-existent app, so we simply
      # assert there are no rows for this application_id.
      {:ok, %{rows: rows}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT processed FROM webhook_events WHERE application_id = $1",
          [uuid_binary]
        )

      assert rows == []
    end

    test "invalid transition does not crash and logs warning" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      logs =
        capture_log(fn ->
          # approved is not valid from submitted
          assert :ok =
                   perform_job(WebhookProcessingWorker, %{
                     "application_id" => app.id,
                     "status" => "approved",
                     "triggered_by" => "webhook"
                   })
        end)

      assert logs =~ "Webhook processing skipped"
      assert logs =~ "invalid_transition"
    end

    test "marks webhook_event as processed even on invalid_transition" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      # Insert a webhook_event row manually
      {:ok, _} =
        SQL.query(
          DebtStalker.Repo,
          """
          INSERT INTO webhook_events (id, application_id, source, payload_hash, verified, processed, inserted_at)
          VALUES ($1, $2, 'provider_es', 'testhash456', true, false, NOW())
          """,
          [Ecto.UUID.bingenerate(), uuid_binary]
        )

      # Run the worker with an invalid transition (approved from submitted)
      assert :ok =
               perform_job(WebhookProcessingWorker, %{
                 "application_id" => app.id,
                 "status" => "approved",
                 "triggered_by" => "webhook"
               })

      # Webhook event should still be marked processed — the worker handled it
      {:ok, %{rows: [[processed_val]]}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT processed FROM webhook_events WHERE application_id = $1",
          [uuid_binary]
        )

      assert processed_val == true
    end
  end
end
