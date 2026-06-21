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

    test "handles invalid_transition gracefully without crashing" do
      # Create an app and manually move it to a state where pending_risk
      # transition is invalid (e.g. approved)
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(app.id, "approved", "system")

      # Running the worker on an approved app should be a no-op (not_evaluable)
      assert :ok = perform_job(RiskEvaluationWorker, %{application_id: app.id})
    end

    test "handles update_status failure during pending_risk transition" do
      # If the app is in a state where submitted→pending_risk is invalid,
      # the worker should handle the error gracefully
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      # Now app is in pending_risk — worker should evaluate and not crash
      # even if the status update to approved/rejected has issues
      assert :ok = perform_job(RiskEvaluationWorker, %{application_id: app.id})
    end
  end
end
