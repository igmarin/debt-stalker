defmodule DebtStalker.Workers.ExternalNotificationWorkerTest do
  use DebtStalker.DataCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  alias DebtStalker.Applications
  alias DebtStalker.Workers.ExternalNotificationWorker
  alias Ecto.Adapters.SQL

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  defp create_approved_app do
    {:ok, app} = Applications.create_application(@valid_es_attrs)
    {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
    {:ok, approved} = Applications.update_status(app.id, "approved", "system")
    approved
  end

  describe "perform/1" do
    test "stores notification for approved application" do
      app = create_approved_app()

      perform_job(ExternalNotificationWorker, %{
        application_id: app.id,
        event_type: "application.status_changed",
        payload: %{"to_status" => "approved"}
      })

      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, %{rows: rows}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT notification_type, status FROM notification_attempts WHERE application_id = $1",
          [uuid_binary]
        )

      assert length(rows) == 1
      [[type, status]] = rows
      assert type == "status_notification"
      assert status == "simulated"
    end

    test "is idempotent — second run does not duplicate" do
      app = create_approved_app()

      perform_job(ExternalNotificationWorker, %{
        application_id: app.id,
        event_type: "application.status_changed",
        payload: %{"to_status" => "approved"}
      })

      perform_job(ExternalNotificationWorker, %{
        application_id: app.id,
        event_type: "application.status_changed",
        payload: %{"to_status" => "approved"}
      })

      {:ok, uuid_binary} = Ecto.UUID.dump(app.id)

      {:ok, %{rows: rows}} =
        SQL.query(
          DebtStalker.Repo,
          "SELECT COUNT(*) FROM notification_attempts WHERE application_id = $1",
          [uuid_binary]
        )

      assert [[1]] = rows
    end

    test "non-terminal app is skipped" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      assert :ok =
               perform_job(ExternalNotificationWorker, %{
                 application_id: app.id,
                 event_type: "application.status_changed",
                 payload: %{"to_status" => "pending_risk"}
               })
    end

    test "unknown app is skipped" do
      assert :ok =
               perform_job(ExternalNotificationWorker, %{
                 application_id: Ecto.UUID.generate(),
                 event_type: "application.status_changed",
                 payload: %{"to_status" => "approved"}
               })
    end
  end
end
