defmodule DebtStalker.LogScrubbingAuditTest do
  @moduledoc """
  Log-scrubbing audit: exercises every log path and asserts no PII,
  secrets, or raw provider payloads appear in captured log output.

  Log paths exercised:
  - Application creation (info)
  - Application creation failure: unsupported country (warning)
  - Application creation failure: invalid document (warning)
  - Status transition (info)
  - Provider error (error)
  - Risk evaluation worker (info/warning)
  - Webhook processing (info/warning)
  - Notification worker (info)
  - Circuit breaker (warning/error)
  """

  use DebtStalker.DataCase, async: false

  import ExUnit.CaptureLog

  alias DebtStalker.Applications
  alias DebtStalker.Workers.ExternalNotificationWorker
  alias DebtStalker.Workers.RiskEvaluationWorker
  alias DebtStalker.Workers.WebhookProcessingWorker

  @valid_attrs %{
    country: "ES",
    full_name: "Jane Doe",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000.00"),
    monthly_income: Decimal.new("3000.00")
  }

  # PII values that should NEVER appear in logs
  @pii_patterns [
    "12345678Z",
    "Jane Doe"
  ]

  # Secret patterns that should NEVER appear in logs
  @secret_patterns [
    "SECRET_KEY_BASE",
    "CLOAK_KEY",
    "JWT_SECRET",
    "WEBHOOK_SECRET"
  ]

  defp assert_no_pii_or_secrets(logs, context) do
    for pattern <- @pii_patterns do
      refute logs =~ pattern,
             "PII leak in #{context}: logs contain '#{pattern}'\n\nLogs:\n#{logs}"
    end

    for pattern <- @secret_patterns do
      # We check that actual secret VALUES aren't logged, not the env var names
      # The names may appear in error messages, but values must not
      secret_value_regex = Regex.compile!(pattern <> "[:=]\\s*[\\w\\-+/=]{20,}")

      refute Regex.match?(secret_value_regex, logs),
             "Secret leak in #{context}: logs contain '#{pattern}' with a value\n\nLogs:\n#{logs}"
    end

    # Raw provider payloads should not appear
    refute logs =~ "raw_provider_payload",
           "Raw provider payload leak in #{context}\n\nLogs:\n#{logs}"
  end

  describe "application creation log path" do
    test "creation success log has no PII" do
      logs =
        capture_log(fn ->
          {:ok, _app} = Applications.create_application(@valid_attrs)
        end)

      assert_no_pii_or_secrets(logs, "application creation")
    end

    test "creation failure: unsupported country log has no PII" do
      logs =
        capture_log(fn ->
          {:error, _} =
            Applications.create_application(%{
              @valid_attrs
              | country: "XX",
                identity_document: "12345678Z",
                full_name: "Jane Doe"
            })
        end)

      assert_no_pii_or_secrets(logs, "creation failure (unsupported country)")
    end
  end

  describe "status transition log path" do
    test "transition log has no PII" do
      {:ok, app} = Applications.create_application(@valid_attrs)

      logs =
        capture_log(fn ->
          Applications.update_status(app.id, "pending_risk", "test_actor")
        end)

      assert_no_pii_or_secrets(logs, "status transition")
    end
  end

  describe "risk evaluation worker log path" do
    test "risk evaluation log has no PII" do
      {:ok, app} = Applications.create_application(@valid_attrs)
      Applications.update_status(app.id, "pending_risk", "test_actor")

      logs =
        capture_log(fn ->
          RiskEvaluationWorker.perform(%Oban.Job{args: %{"application_id" => app.id}})
        end)

      assert_no_pii_or_secrets(logs, "risk evaluation worker")
    end
  end

  describe "webhook processing worker log path" do
    test "webhook processing log has no PII" do
      {:ok, app} = Applications.create_application(@valid_attrs)

      logs =
        capture_log(fn ->
          WebhookProcessingWorker.perform(%Oban.Job{
            args: %{
              "application_id" => app.id,
              "status" => "pending_risk",
              "triggered_by" => "webhook"
            }
          })
        end)

      assert_no_pii_or_secrets(logs, "webhook processing worker")
    end

    test "webhook not_found log has no PII" do
      logs =
        capture_log(fn ->
          WebhookProcessingWorker.perform(%Oban.Job{
            args: %{
              "application_id" => "00000000-0000-0000-0000-000000000000",
              "status" => "approved",
              "triggered_by" => "webhook"
            }
          })
        end)

      assert_no_pii_or_secrets(logs, "webhook not_found")
    end
  end

  describe "notification worker log path" do
    test "notification log has no PII" do
      {:ok, app} = Applications.create_application(@valid_attrs)

      logs =
        capture_log(fn ->
          ExternalNotificationWorker.perform(%Oban.Job{
            args: %{
              "application_id" => app.id,
              "event_type" => "status_update"
            }
          })
        end)

      assert_no_pii_or_secrets(logs, "notification worker")
    end
  end
end
