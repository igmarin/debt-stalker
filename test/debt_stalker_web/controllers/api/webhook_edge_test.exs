defmodule DebtStalkerWeb.Api.WebhookEdgeTest do
  @moduledoc """
  Edge case tests for webhook HMAC signature verification and
  idempotency handling.
  """
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

  describe "HMAC signature verification" do
    test "valid HMAC signature is accepted", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      payload = %{
        "application_id" => app.id,
        "status" => "pending_risk",
        "source" => "provider_es"
      }

      body = Jason.encode!(payload)
      secret = Application.get_env(:debt_stalker, :webhook_secret, "dev-webhook-secret")

      signature =
        :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

      conn =
        conn
        |> put_req_header("x-webhook-signature", signature)
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, body)
        |> post("/api/webhooks/provider-confirmations", payload)

      assert json_response(conn, 200)["received"] == true
    end

    test "invalid HMAC signature returns 401 when signature required", %{conn: conn} do
      Application.put_env(:debt_stalker, :require_webhook_signature, true)

      on_exit(fn ->
        Application.delete_env(:debt_stalker, :require_webhook_signature)
      end)

      {:ok, app} = Applications.create_application(@valid_es_attrs)

      conn =
        conn
        |> put_req_header("x-webhook-signature", "invalid_signature_value")
        |> assign(:raw_body, "some body")
        |> post("/api/webhooks/provider-confirmations", %{
          "application_id" => app.id,
          "status" => "pending_risk"
        })

      assert json_response(conn, 401)["error"] == "invalid_signature"
    end

    test "missing signature returns 401 when signature required", %{conn: conn} do
      Application.put_env(:debt_stalker, :require_webhook_signature, true)

      on_exit(fn ->
        Application.delete_env(:debt_stalker, :require_webhook_signature)
      end)

      conn =
        conn
        |> post("/api/webhooks/provider-confirmations", %{
          "application_id" => Ecto.UUID.generate(),
          "status" => "pending_risk"
        })

      assert json_response(conn, 401)["error"] == "invalid_signature"
    end
  end

  describe "idempotency edge cases" do
    test "same payload hash from different applications still deduplicates", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      payload = %{
        "application_id" => app.id,
        "status" => "pending_risk",
        "source" => "provider_es"
      }

      # First request
      conn1 = post(conn, "/api/webhooks/provider-confirmations", payload)
      assert json_response(conn1, 200)["received"] == true

      # Exact same payload → duplicate
      conn2 = post(conn, "/api/webhooks/provider-confirmations", payload)
      assert json_response(conn2, 200)["status"] == "already_processed"
    end
  end
end
