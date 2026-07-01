defmodule DebtStalker.Countries.COTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DebtStalker.Countries.CO

  describe "validate_document/1" do
    # Cédula de Ciudadanía: 8-10 numeric digits, no checksum letter
    @valid_ccs ["12345678", "123456789", "1234567890", "1053812345", "000000008"]

    test "accepts valid CC formats (8-10 numeric digits)" do
      for cc <- @valid_ccs do
        assert :ok = CO.validate_document(cc), "Expected #{cc} to be valid"
      end
    end

    test "rejects CC with fewer than 8 digits" do
      assert {:error, _} = CO.validate_document("1234567")
    end

    test "rejects CC with more than 10 digits" do
      assert {:error, _} = CO.validate_document("12345678901")
    end

    test "rejects CC with non-numeric characters" do
      assert {:error, _} = CO.validate_document("1234567A")
      assert {:error, _} = CO.validate_document("12345678Z")
      assert {:error, _} = CO.validate_document("1234-5678")
    end

    test "rejects empty string" do
      assert {:error, _} = CO.validate_document("")
    end

    test "rejects whitespace-only input" do
      assert {:error, _} = CO.validate_document("   ")
    end

    test "trims whitespace around valid CC" do
      assert :ok = CO.validate_document(" 1234567890 ")
    end

    property "any 8-10 digit string is valid" do
      digits = Enum.to_list(?0..?9)

      check all(
              length <- integer(8..10),
              doc <- string(digits, length: length)
            ) do
        assert :ok = CO.validate_document(doc)
      end
    end
  end

  describe "validate_financials/1" do
    test "below both thresholds does not flag review" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("5000")
        })

      assert result.additional_review_required == false
      assert result.reasons == []
    end

    test "amount > 12x monthly income flags additional review" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("24001"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("0")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
    end

    test "amount exactly 12x income does NOT flag" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("24000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("0")
        })

      refute "income_ratio_exceeded" in result.reasons
    end

    test "provider_debt + amount > 22x monthly income flags additional review" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("15000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("35000")
        })

      assert result.additional_review_required == true
      assert "debt_ratio_exceeded" in result.reasons
    end

    test "provider_debt + amount exactly 22x income does NOT flag" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("14000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("30000")
        })

      refute "debt_ratio_exceeded" in result.reasons
    end

    test "both thresholds can be flagged simultaneously" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("30000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("30000")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
      assert "debt_ratio_exceeded" in result.reasons
    end

    test "defaults provider_debt to 0 when not provided" do
      result =
        CO.validate_financials(%{
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == false
    end
  end

  describe "additional_review_required?/1" do
    test "delegates to validate_financials logic" do
      assert CO.additional_review_required?(%{
               requested_amount: Decimal.new("30000"),
               monthly_income: Decimal.new("2000"),
               provider_debt: Decimal.new("0")
             })

      refute CO.additional_review_required?(%{
               requested_amount: Decimal.new("5000"),
               monthly_income: Decimal.new("2000"),
               provider_debt: Decimal.new("0")
             })
    end
  end

  describe "acceptable_risk_score?/1" do
    test "returns true when datacredito_score is at or above 580" do
      assert CO.acceptable_risk_score?(%{"risk_indicators" => %{"datacredito_score" => 580}})
      assert CO.acceptable_risk_score?(%{"risk_indicators" => %{"datacredito_score" => 700}})
    end

    test "returns false when datacredito_score is below 580" do
      refute CO.acceptable_risk_score?(%{"risk_indicators" => %{"datacredito_score" => 579}})
      refute CO.acceptable_risk_score?(%{"risk_indicators" => %{"datacredito_score" => 400}})
    end

    test "returns false when provider summary has no datacredito_score (fail-safe)" do
      refute CO.acceptable_risk_score?(%{})
      refute CO.acceptable_risk_score?(%{"risk_indicators" => %{}})
      refute CO.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 700}})
      refute CO.acceptable_risk_score?(%{"risk_indicators" => %{"buro_score" => 700}})
    end
  end

  describe "allowed_status_transitions/0" do
    test "has expected transition keys" do
      transitions = CO.allowed_status_transitions()
      assert Map.has_key?(transitions, "submitted")
      assert Map.has_key?(transitions, "pending_risk")
      assert Map.has_key?(transitions, "additional_review")
      assert Map.has_key?(transitions, "provider_error")
      assert "approved" in transitions["pending_risk"]
      assert "rejected" in transitions["pending_risk"]
    end
  end

  describe "risk_score_threshold/0" do
    test "returns 580" do
      assert CO.risk_score_threshold() == 580
    end
  end

  describe "document_hint/0" do
    test "returns a Cédula example" do
      assert CO.document_hint() =~ "Cédula"
    end
  end

  describe "currency_symbol/0" do
    test "returns the Colombian peso symbol" do
      assert CO.currency_symbol() == "$"
    end
  end

  describe "random_identity_document/0" do
    test "generates a valid CC" do
      doc = CO.random_identity_document()
      assert :ok = CO.validate_document(doc)
    end
  end
end
