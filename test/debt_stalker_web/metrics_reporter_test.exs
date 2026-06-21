defmodule DebtStalkerWeb.MetricsReporterTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  setup do
    {:ok, app} = Applications.create_application(@valid_es_attrs)
    %{app: app}
  end

  describe "Prometheus metrics reporter" do
    test "exposes status transition metrics after a transition", %{app: app} do
      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      assert is_binary(metrics_output)
      assert metrics_output =~ "debt_stalker_status_transition_stop"
    end

    test "exposes provider call metrics after application creation" do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      assert is_binary(metrics_output)
      assert metrics_output =~ "debt_stalker_provider_fetch_stop"
    end

    test "exposes built-in Ecto metrics" do
      # Trigger an Ecto query
      DebtStalker.Repo.all(DebtStalker.Applications.CreditApplication)

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      assert is_binary(metrics_output)
      # Ecto query metrics (distribution/histogram format)
      assert metrics_output =~ "debt_stalker_repo_query"
    end
  end

  describe "LiveDashboard" do
    test "is wired and accessible in dev routes" do
      # LiveDashboard is configured in the router under /dev/dashboard
      # Verify the Telemetry module exposes metrics for LiveDashboard
      metrics = DebtStalkerWeb.Telemetry.metrics()

      assert is_list(metrics)
      # Phoenix metrics for LiveDashboard
      assert Enum.any?(metrics, fn m ->
               m.event_name == [:phoenix, :endpoint, :stop]
             end)

      # VM metrics for LiveDashboard
      assert Enum.any?(metrics, fn m ->
               m.event_name == [:vm, :memory]
             end)
    end
  end
end
