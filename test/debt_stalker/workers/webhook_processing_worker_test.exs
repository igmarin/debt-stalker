defmodule DebtStalker.Workers.WebhookProcessingWorkerTest do
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
          INSERT INTO webhook_events (id, application_id, source, payload_hash, verified, processed, raw_payload, inserted_at)
          VALUES ($1, $2, 'provider_es', 'testhash123', true, false, '{}'::jsonb, NOW())
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

    test "non-existent application does not crash and logs warning" do
      fake_id = Ecto.UUID.generate()

      logs =
        capture_log(fn ->
          assert :ok =
                   perform_job(WebhookProcessingWorker, %{
                     "application_id" => fake_id,
                     "status" => "approved",
                     "triggered_by" => "webhook"
                   })
        end)

      assert logs =~ "Webhook processing skipped"
      assert logs =~ "not_found"
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
  end
end
