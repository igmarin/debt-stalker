defmodule DebtStalker.BusinessMetricsTest do
  use DebtStalker.DataCase, async: false

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "business metrics" do
    test "applications_created counter increments on application creation" do
      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      initial_count =
        extract_labeled_counter(
          metrics_output,
          "debt_stalker_applications_created_count",
          "country",
          "ES"
        )

      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      metrics_output2 = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      final_count =
        extract_labeled_counter(
          metrics_output2,
          "debt_stalker_applications_created_count",
          "country",
          "ES"
        )

      assert final_count >= initial_count + 1.0
    end

    test "provider_latency histogram tracks provider call duration" do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      assert metrics_output =~ "debt_stalker_provider_latency"
      assert metrics_output =~ "_bucket{"
    end

    test "status_transition counter tracks transitions by to_status" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      initial =
        extract_labeled_counter(
          metrics_output,
          "debt_stalker_status_transition_stop_count",
          "pending_risk"
        )

      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      metrics_output2 = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      final =
        extract_labeled_counter(
          metrics_output2,
          "debt_stalker_status_transition_stop_count",
          "pending_risk"
        )

      assert final >= initial + 1.0
    end

    test "oban_jobs counter tracks job execution by worker and result" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      :ok =
        Oban.Testing.perform_job(
          DebtStalker.Workers.RiskEvaluationWorker,
          %{"application_id" => app.id},
          queue: :events
        )

      metrics_output = TelemetryMetricsPrometheus.Core.scrape(:prometheus_metrics)

      assert metrics_output =~ "debt_stalker_oban_jobs"
    end
  end

  defp extract_labeled_counter(output, metric_name, label_value) do
    pattern =
      Regex.compile!(
        "^#{metric_name}\\{[^}]*to_status=\"#{label_value}\"[^}]*\\}\\s+(\\d+(?:\\.\\d+)?)$",
        "m"
      )

    case Regex.run(pattern, output) do
      [_, value] -> parse_number(value)
      nil -> 0.0
    end
  end

  defp extract_labeled_counter(output, metric_name, label_key, label_value) do
    pattern =
      Regex.compile!(
        "^#{metric_name}\\{[^}]*#{label_key}=\"#{label_value}\"[^}]*\\}\\s+(\\d+(?:\\.\\d+)?)$",
        "m"
      )

    case Regex.run(pattern, output) do
      [_, value] -> parse_number(value)
      nil -> 0.0
    end
  end

  defp parse_number(value) do
    if String.contains?(value, ".") do
      String.to_float(value)
    else
      String.to_integer(value) * 1.0
    end
  end
end
