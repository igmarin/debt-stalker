defmodule DebtStalker.RiskTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias DebtStalker.Risk

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

  describe "risk_score_threshold/1" do
    test "returns configured threshold for supported countries" do
      assert 650 = Risk.risk_score_threshold("ES")
      assert 600 = Risk.risk_score_threshold("MX")
    end

    test "returns nil for unsupported countries" do
      assert is_nil(Risk.risk_score_threshold("XX"))
    end
  end

  describe "evaluate/1" do
    test "returns approved for normal app with good credit score" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "returns additional_review when thresholds exceeded" do
      {:ok, app} = Applications.create_application(@over_threshold_attrs)
      assert {:ok, "additional_review"} = Risk.evaluate(app)
    end

    test "returns rejected when credit score below threshold" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      # Override provider_summary with low credit score
      app = %{app | provider_summary: %{"risk_indicators" => %{"credit_score" => 500}}}

      assert {:ok, "rejected"} = Risk.evaluate(app)
    end

    test "returns approved when credit score exactly at threshold (650)" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      app = %{app | provider_summary: %{"risk_indicators" => %{"credit_score" => 650}}}
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "returns approved for MX app with good buro score" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      # Override with good buro score
      app = %{app | provider_summary: %{"risk_indicators" => %{"buro_score" => 700}}}
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "returns rejected for MX app with low buro score" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      app = %{app | provider_summary: %{"risk_indicators" => %{"buro_score" => 500}}}
      assert {:ok, "rejected"} = Risk.evaluate(app)
    end

    test "extracts provider_debt from provider summary for MX" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("15000"),
          monthly_income: Decimal.new("2000")
        })

      # Override with high existing debt (debt + amount > 18x income)
      app = %{
        app
        | provider_summary: %{
            "risk_indicators" => %{"buro_score" => 700, "existing_debt" => "25000"}
          }
      }

      assert {:ok, "additional_review"} = Risk.evaluate(app)
    end

    test "handles missing provider_summary gracefully (fail-safe: rejected)" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      app = %{app | provider_summary: nil}
      # With no provider summary, risk score is not acceptable (fail-safe)
      assert {:ok, "rejected"} = Risk.evaluate(app)
    end

    test "handles invalid existing_debt value gracefully" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      app = %{
        app
        | provider_summary: %{
            "risk_indicators" => %{"buro_score" => 700, "existing_debt" => "not-a-number"}
          }
      }

      # Should not crash — defaults to 0 debt
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "returns error for unsupported country" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      app = %{app | country: "XX"}

      assert {:error, :unsupported_country} = Risk.evaluate(app)
    end

    test "delegates to country module for ES with high credit score" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      app = %{app | provider_summary: %{"risk_indicators" => %{"credit_score" => 750}}}
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "delegates to country module for ES with low credit score" do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      app = %{app | provider_summary: %{"risk_indicators" => %{"credit_score" => 400}}}
      assert {:ok, "rejected"} = Risk.evaluate(app)
    end

    test "delegates to country module for MX with high buro score" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("5000"),
          monthly_income: Decimal.new("2000")
        })

      app = %{app | provider_summary: %{"risk_indicators" => %{"buro_score" => 800}}}
      assert {:ok, "approved"} = Risk.evaluate(app)
    end

    test "delegates to country module for MX with low buro score" do
      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Carlos Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("5000"),
          monthly_income: Decimal.new("2000")
        })

      app = %{app | provider_summary: %{"risk_indicators" => %{"buro_score" => 400}}}
      assert {:ok, "rejected"} = Risk.evaluate(app)
    end
  end
end
