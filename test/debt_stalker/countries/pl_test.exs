defmodule DebtStalker.Countries.PLTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DebtStalker.Countries.PL

  @valid_pesel "02070803628"

  describe "validate_document/1" do
    test "accepts valid PESEL" do
      assert :ok = PL.validate_document(@valid_pesel)
    end

    test "rejects PESEL with wrong length" do
      assert {:error, _} = PL.validate_document("0207080362")
      assert {:error, _} = PL.validate_document("020708036281")
    end

    test "rejects PESEL with letters" do
      assert {:error, _} = PL.validate_document("0207080362A")
    end

    test "rejects PESEL with wrong checksum" do
      assert {:error, _} = PL.validate_document("02070803621")
    end

    test "rejects empty string" do
      assert {:error, _} = PL.validate_document("")
    end

    test "rejects nil-like input" do
      assert {:error, _} = PL.validate_document("   ")
    end

    test "generated random identity documents are valid" do
      for _ <- 1..50 do
        assert :ok = PL.validate_document(PL.random_identity_document())
      end
    end

    property "any 10 digits plus correct checksum is valid" do
      check all(digits <- list_of(integer(0..9), length: 10)) do
        checksum = pesel_checksum(digits)
        pesel = digits |> List.insert_at(-1, checksum) |> Enum.map_join(&Integer.to_string/1)

        assert :ok = PL.validate_document(pesel)
      end
    end
  end

  describe "validate_financials/1" do
    test "amount <= 60000 and ratio <= 10x does not flag review" do
      result =
        PL.validate_financials(%{
          requested_amount: Decimal.new("5000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == false
      assert result.reasons == []
    end

    test "amount > 60000 flags additional review" do
      result =
        PL.validate_financials(%{
          requested_amount: Decimal.new("60001"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == true
      assert "amount_exceeds_threshold" in result.reasons
    end

    test "amount > 10x monthly income flags additional review" do
      result =
        PL.validate_financials(%{
          requested_amount: Decimal.new("20001"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == true
      assert "income_ratio_exceeded" in result.reasons
    end

    test "amount exactly 10x income does NOT flag" do
      result =
        PL.validate_financials(%{
          requested_amount: Decimal.new("20000"),
          monthly_income: Decimal.new("2000")
        })

      refute "income_ratio_exceeded" in result.reasons
    end

    test "both thresholds can be flagged simultaneously" do
      result =
        PL.validate_financials(%{
          requested_amount: Decimal.new("70000"),
          monthly_income: Decimal.new("2000")
        })

      assert result.additional_review_required == true
      assert "amount_exceeds_threshold" in result.reasons
      assert "income_ratio_exceeded" in result.reasons
    end
  end

  describe "additional_review_required?/1" do
    test "delegates to validate_financials logic" do
      assert PL.additional_review_required?(%{
               requested_amount: Decimal.new("70000"),
               monthly_income: Decimal.new("2000")
             })

      refute PL.additional_review_required?(%{
               requested_amount: Decimal.new("5000"),
               monthly_income: Decimal.new("2000")
             })
    end
  end

  describe "acceptable_risk_score?/1" do
    test "returns true when bik_score is at or above 650" do
      assert PL.acceptable_risk_score?(%{"risk_indicators" => %{"bik_score" => 650}})
      assert PL.acceptable_risk_score?(%{"risk_indicators" => %{"bik_score" => 700}})
    end

    test "returns false when bik_score is below 650" do
      refute PL.acceptable_risk_score?(%{"risk_indicators" => %{"bik_score" => 649}})
      refute PL.acceptable_risk_score?(%{"risk_indicators" => %{"bik_score" => 500}})
    end

    test "returns false when provider summary has no bik_score (fail-safe)" do
      refute PL.acceptable_risk_score?(%{})
      refute PL.acceptable_risk_score?(%{"risk_indicators" => %{}})
      refute PL.acceptable_risk_score?(%{"risk_indicators" => %{"credit_score" => 700}})
    end
  end

  describe "document_hint/0" do
    test "returns a PESEL example" do
      assert PL.document_hint() =~ "PESEL"
    end
  end

  describe "currency_symbol/0" do
    test "returns the Polish zloty symbol" do
      assert PL.currency_symbol() == "zł"
    end
  end

  describe "allowed_status_transitions/0" do
    test "returns valid transition map" do
      transitions = PL.allowed_status_transitions()
      assert is_map(transitions)
      assert Map.has_key?(transitions, "submitted")
      assert "pending_risk" in transitions["submitted"]
    end
  end

  # Helper: compute the PESEL checksum digit
  defp pesel_checksum(digits) do
    weights = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]

    digits
    |> Enum.take(10)
    |> Enum.zip(weights)
    |> Enum.map(fn {digit, weight} -> digit * weight end)
    |> Enum.sum()
    |> rem(10)
    |> then(fn remainder -> rem(10 - remainder, 10) end)
  end
end
