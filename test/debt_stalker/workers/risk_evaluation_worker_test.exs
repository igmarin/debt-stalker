defmodule DebtStalker.Workers.RiskEvaluationWorkerTest do
  use DebtStalker.DataCase, async: false
  use Oban.Testing, repo: DebtStalker.Repo

  alias DebtStalker.Applications
  alias DebtStalker.Workers.RiskEvaluationWorker

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  @over_threshold_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("20000"),
    monthly_income: Decimal.new("2000")
  }

  describe "perform/1" do
    test "moves submitted → pending_risk → approved for normal app" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      perform_job(RiskEvaluationWorker, %{application_id: app.id})

      {:ok, updated} = Applications.get_application(app.id)
      assert updated.status == "approved"
    end

    test "moves to additional_review when thresholds exceeded" do
      {:ok, app} = Applications.create_application(@over_threshold_attrs)

      perform_job(RiskEvaluationWorker, %{application_id: app.id})

      {:ok, updated} = Applications.get_application(app.id)
      assert updated.status == "additional_review"
    end

    test "is idempotent — re-running on already approved app is no-op" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      perform_job(RiskEvaluationWorker, %{application_id: app.id})
      {:ok, after_first} = Applications.get_application(app.id)
      assert after_first.status == "approved"

      # Second run should be a no-op
      perform_job(RiskEvaluationWorker, %{application_id: app.id})
      {:ok, after_second} = Applications.get_application(app.id)
      assert after_second.status == "approved"
    end

    test "non-existent application does not crash" do
      assert :ok = perform_job(RiskEvaluationWorker, %{application_id: Ecto.UUID.generate()})
    end
  end
end
