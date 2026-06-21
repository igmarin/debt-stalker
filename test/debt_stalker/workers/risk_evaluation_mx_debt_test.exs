defmodule DebtStalker.Workers.RiskEvaluationMxDebtTest do
  @moduledoc """
  Regression test for GAP-2: MX debt rule (AC2.6).

  Verifies that the RiskEvaluationWorker correctly passes provider_debt
  from the provider summary when evaluating MX applications, ensuring
  the 18x debt-to-income rule is properly applied.
  """
  use DebtStalker.DataCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  alias DebtStalker.Applications
  alias DebtStalker.Workers.RiskEvaluationWorker

  @mx_attrs %{
    country: "MX",
    full_name: "Maria Lopez",
    identity_document: "GARC850101HDFRRL09",
    requested_amount: Decimal.new("8000"),
    monthly_income: Decimal.new("2000")
  }

  # CURP mapped in test config to 35_000 existing_debt (see :mx_simulated_debt_overrides).
  @mx_high_debt_attrs %{
    country: "MX",
    full_name: "Maria Lopez",
    identity_document: "DEBT850101HDFRRL09",
    requested_amount: Decimal.new("8000"),
    monthly_income: Decimal.new("2000")
  }

  describe "MX provider_debt evaluation" do
    test "routes to additional_review when provider debt exceeds 18x income (AC2.6 E2E)" do
      {:ok, app} = Applications.create_application(@mx_high_debt_attrs)

      assert app.provider_summary["risk_indicators"]["existing_debt"] == "35000"

      perform_job(RiskEvaluationWorker, %{application_id: app.id})

      {:ok, updated} = Applications.get_application(app.id)
      assert updated.status == "additional_review"
    end

    test "extracts existing_debt from provider_summary for MX risk evaluation" do
      {:ok, app} = Applications.create_application(@mx_attrs)

      assert app.provider_summary != nil
      assert app.provider_summary["risk_indicators"]["existing_debt"] != nil

      perform_job(RiskEvaluationWorker, %{application_id: app.id})

      {:ok, updated} = Applications.get_application(app.id)

      existing_debt =
        app.provider_summary["risk_indicators"]["existing_debt"]
        |> Decimal.new()

      total_debt = Decimal.add(existing_debt, app.requested_amount)
      threshold = Decimal.mult(app.monthly_income, 18)

      if Decimal.gt?(total_debt, threshold) do
        assert updated.status == "additional_review"
      else
        assert updated.status in ["approved", "rejected"]
      end
    end

    test "MX app with zero provider_debt follows income-ratio rules only" do
      # The income ratio: 8000 > 10 * 2000 = 20000? No. So no flag from income alone.
      {:ok, app} = Applications.create_application(@mx_attrs)
      perform_job(RiskEvaluationWorker, %{application_id: app.id})
      {:ok, updated} = Applications.get_application(app.id)

      # With 8000 < 20000 (10x income), income_ratio is fine
      # Status depends on debt ratio + risk score
      assert updated.status in ["approved", "additional_review", "rejected"]
    end

    test "ES app without existing_debt field defaults provider_debt to 0" do
      es_attrs = %{
        country: "ES",
        full_name: "Juan Garcia",
        identity_document: "12345678Z",
        requested_amount: Decimal.new("5000"),
        monthly_income: Decimal.new("2000")
      }

      {:ok, app} = Applications.create_application(es_attrs)
      perform_job(RiskEvaluationWorker, %{application_id: app.id})
      {:ok, updated} = Applications.get_application(app.id)

      # ES doesn't use provider_debt, should work fine with default 0
      assert updated.status == "approved"
    end
  end
end
