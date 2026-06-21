defmodule DebtStalkerWeb.Api.WebhookControllerTest do
  use DebtStalkerWeb.ConnCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "POST /api/webhooks/provider-confirmations" do
    test "accepts webhook and enqueues processing", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      conn =
        conn
        |> post("/api/webhooks/provider-confirmations", %{
          "application_id" => app.id,
          "status" => "approved",
          "source" => "provider_es"
        })

      assert json_response(conn, 200)["received"] == true
      assert_enqueued(worker: DebtStalker.Workers.WebhookProcessingWorker)
    end

    test "rejects duplicate webhook (idempotent)", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      payload = %{
        "application_id" => app.id,
        "status" => "pending_risk",
        "source" => "provider_es"
      }

      post(conn, "/api/webhooks/provider-confirmations", payload)
      conn2 = post(conn, "/api/webhooks/provider-confirmations", payload)

      assert json_response(conn2, 200)["status"] == "already_processed"
    end

    test "webhook without application_id is accepted but no job enqueued", %{conn: conn} do
      conn =
        conn
        |> post("/api/webhooks/provider-confirmations", %{
          "source" => "provider_es",
          "info" => "general update"
        })

      assert json_response(conn, 200)["received"] == true
      refute_enqueued(worker: DebtStalker.Workers.WebhookProcessingWorker)
    end
  end
end
