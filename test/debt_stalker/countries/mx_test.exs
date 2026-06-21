defmodule DebtStalker.Countries.MXTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DebtStalker.Countries.MX

  describe "validate_document/1" do
    # CURP: 18 chars, uppercase alphanumeric pattern
    # Format: AAAA######SSSSSSCC (4 letters, 6 digits, 6 chars, 2 chars)
    @valid_curps ["GARC850101HDFRRL09", "LOPE900215MMCPZN02", "MAMA750530HDFRRN08"]

    test "accepts valid CURP formats" do
      for curp <- @valid_curps do
        assert :ok = MX.validate_document(curp), "Expected #{curp} to be valid"
      end
    end

    test "rejects CURP with wrong length" do
      assert {:error, _} = MX.validate_document("GARC850101HDFRRL0")
      assert {:error, _} = MX.validate_document("GARC850101HDFRRL099")
    end

    test "rejects CURP with lowercase" do
      assert {:error, _} = MX.validate_document("garc850101hdfrrl09")
    end

    test "rejects empty string" do
      assert {:error, _} = MX.validate_document("")
    end

    test "rejects CURP with special characters" do
      assert {:error, _} = MX.validate_document("GARC850101HDFR-L09")
    end

    property "any 18-char uppercase alphanumeric with valid structure is accepted" do
      uppercase = Enum.to_list(?A..?Z)
      digits = Enum.to_list(?0..?9)
      alphanumeric_upper = uppercase ++ digits

      check all(
              letters <- string(uppercase, length: 4),
              digit_part <- string(digits, length: 6),
              middle <- string(alphanumeric_upper, length: 6),
              tail <- string(alphanumeric_upper, length: 2)
            ) do
        curp = letters <> digit_part <> middle <> tail
        assert :ok = MX.validate_document(curp)
      end
    end
  end

  describe "validate_financials/1" do
    test "below both thresholds does not flag review" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("5000")
        })

      assert result.additional_review_required == false
      assert result.reasons == []
    end

    test "amount > 10x monthly income flags additional review" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("20001"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("0")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
    end

    test "amount exactly 10x income does NOT flag" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("20000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("0")
        })

      refute "income_ratio_exceeded" in result.reasons
    end

    test "provider_debt + amount > 18x monthly income flags additional review" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("15000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("25000")
        })

      assert result.additional_review_required == true
      assert "debt_ratio_exceeded" in result.reasons
    end

    test "provider_debt + amount exactly 18x income does NOT flag" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("11000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("25000")
        })

      refute "debt_ratio_exceeded" in result.reasons
    end

    test "both thresholds can be flagged simultaneously" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("25000"),
          monthly_income: Decimal.new("2000"),
          provider_debt: Decimal.new("25000")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
      assert "debt_ratio_exceeded" in result.reasons
    end

    test "defaults provider_debt to 0 when not provided" do
      result =
        MX.validate_financials(%{
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == false
    end
  end

  describe "additional_review_required?/1" do
    test "delegates to validate_financials logic" do
      assert MX.additional_review_required?(%{
               requested_amount: Decimal.new("25000"),
               monthly_income: Decimal.new("2000"),
               provider_debt: Decimal.new("0")
             })

      refute MX.additional_review_required?(%{
               requested_amount: Decimal.new("5000"),
               monthly_income: Decimal.new("2000"),
               provider_debt: Decimal.new("0")
             })
    end
  end
end
