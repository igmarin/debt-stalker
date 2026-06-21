defmodule DebtStalker.StructuredLoggingTest do
  use DebtStalker.DataCase, async: false

  import ExUnit.CaptureLog
  require Logger

  alias DebtStalker.Applications

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    :ok
  end

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "structured logging" do
    test "application creation emits log message" do
      log =
        capture_log([level: :info], fn ->
          {:ok, _app} = Applications.create_application(@valid_es_attrs)
        end)

      assert log =~ "Application created"
    end

    test "status transition emits log message" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      log =
        capture_log([level: :info], fn ->
          {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
        end)

      assert log =~ "Status transition completed"
    end

    test "validation failure emits warning log" do
      log =
        capture_log([level: :warning], fn ->
          {:error, _} =
            Applications.create_application(%{
              country: "XX",
              full_name: "Test",
              identity_document: "12345678Z",
              requested_amount: Decimal.new("5000"),
              monthly_income: Decimal.new("2000")
            })
        end)

      assert log =~ "Application creation failed"
    end

    test "provider error emits error log" do
      # Use a document that triggers provider unavailability
      log =
        capture_log([level: :error], fn ->
          {:ok, _app} =
            Applications.create_application(%{
              country: "ES",
              full_name: "Test",
              identity_document: "00000000T",
              requested_amount: Decimal.new("5000"),
              monthly_income: Decimal.new("2000")
            })
        end)

      assert log =~ "Provider error"
    end

    test "log output does not contain full identity document (PII redaction)" do
      log =
        capture_log([level: :info], fn ->
          {:ok, _app} = Applications.create_application(@valid_es_attrs)
        end)

      # The full DNI "12345678Z" must never appear in logs
      refute log =~ "12345678Z"
    end

    test "logger_json formatter is configured" do
      {:ok, config} = :logger.get_handler_config(:default)
      {formatter_module, _opts} = config.formatter
      assert formatter_module == LoggerJSON.Formatters.Basic
    end
  end
end
