defmodule DebtStalker.Countries.ESTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DebtStalker.Countries.ES

  describe "validate_document/1" do
    # Valid DNI: 8 digits + 1 letter (checksum)
    @valid_dnis ["12345678Z", "00000000T", "99999999R", "11111111H"]

    test "accepts valid DNI formats" do
      for dni <- @valid_dnis do
        assert :ok = ES.validate_document(dni), "Expected #{dni} to be valid"
      end
    end

    test "rejects DNI with wrong checksum letter" do
      assert {:error, _} = ES.validate_document("12345678A")
    end

    test "rejects DNI with too few digits" do
      assert {:error, _} = ES.validate_document("1234567Z")
    end

    test "rejects DNI with too many digits" do
      assert {:error, _} = ES.validate_document("123456789Z")
    end

    test "rejects DNI with no letter" do
      assert {:error, _} = ES.validate_document("123456789")
    end

    test "rejects empty string" do
      assert {:error, _} = ES.validate_document("")
    end

    test "rejects nil-like input" do
      assert {:error, _} = ES.validate_document("   ")
    end

    property "any 8-digit + correct checksum letter is valid" do
      check all(digits <- integer(0..99_999_999)) do
        padded = digits |> Integer.to_string() |> String.pad_leading(8, "0")
        letter = dni_checksum_letter(digits)
        dni = padded <> letter
        assert :ok = ES.validate_document(dni)
      end
    end
  end

  describe "validate_financials/1" do
    test "amount <= 15000 and ratio <= 12x does not flag review" do
      result =
        ES.validate_financials(%{
          requested_amount: Decimal.new("15000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == false
      assert result.reasons == []
    end

    test "amount > 15000 flags additional review" do
      result =
        ES.validate_financials(%{
          requested_amount: Decimal.new("15001"),
          monthly_income: Decimal.new("5000")
        })

      assert result.additional_review_required == true
      assert "amount_exceeds_threshold" in result.reasons
    end

    test "amount > 12x monthly income flags additional review" do
      result =
        ES.validate_financials(%{
          requested_amount: Decimal.new("24001"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
    end

    test "amount exactly 12x income does NOT flag" do
      result =
        ES.validate_financials(%{
          requested_amount: Decimal.new("24000"),
          monthly_income: Decimal.new("2000")
        })

      refute "income_ratio_exceeded" in result.reasons
    end

    test "both thresholds can be flagged simultaneously" do
      result =
        ES.validate_financials(%{
          requested_amount: Decimal.new("25000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == true
      assert "amount_exceeds_threshold" in result.reasons
      assert "income_ratio_exceeded" in result.reasons
    end
  end

  describe "additional_review_required?/1" do
    test "delegates to validate_financials logic" do
      assert ES.additional_review_required?(%{
               requested_amount: Decimal.new("20000"),
               monthly_income: Decimal.new("2000")
             })

      refute ES.additional_review_required?(%{
               requested_amount: Decimal.new("5000"),
               monthly_income: Decimal.new("2000")
             })
    end
  end

  describe "acceptable_risk_score?/1" do
    test "returns true when credit_score is at or above 650" do
      assert ES.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 650}})
      assert ES.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 700}})
    end

    test "returns false when credit_score is below 650" do
      refute ES.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 649}})
      refute ES.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 500}})
    end

    test "returns false when provider summary has no credit_score (fail-safe)" do
      refute ES.acceptable_risk_score?(%{})
      refute ES.acceptable_risk_score?(%{"risk_indicators" => %{}})
      refute ES.acceptable_risk_score?(%{"risk_indicators" => %{"buro_score" => 700}})
    end
  end

  describe "document_hint/0" do
    test "returns a DNI example" do
      assert ES.document_hint() =~ "DNI"
    end
  end

  # Helper: compute the DNI checksum letter
  defp dni_checksum_letter(number) do
    letters = "TRWAGMYFPDXBNJZSQVHLCKE"
    index = rem(number, 23)
    String.at(letters, index)
  end
end
