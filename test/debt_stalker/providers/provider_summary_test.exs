defmodule DebtStalker.Providers.ProviderSummaryTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.ProviderSummary

  describe "new/1" do
    test "creates a summary with required fields" do
      summary =
        ProviderSummary.new(%{
          provider_status: "active",
          risk_indicators: %{"score" => 750},
          normalized_data: %{"bank_name" => "Test Bank"}
        })

      assert %ProviderSummary{} = summary
      assert summary.provider_status == "active"
      assert summary.risk_indicators == %{"score" => 750}
      assert summary.normalized_data == %{"bank_name" => "Test Bank"}
    end

    test "defaults risk_indicators and normalized_data to empty maps" do
      summary = ProviderSummary.new(%{provider_status: "active"})
      assert summary.risk_indicators == %{}
      assert summary.normalized_data == %{}
    end

    test "raises on missing provider_status" do
      assert_raise KeyError, fn ->
        ProviderSummary.new(%{risk_indicators: %{}})
      end
    end
  end

  describe "to_map/1" do
    test "converts summary to a string-keyed map" do
      summary =
        ProviderSummary.new(%{
          provider_status: "active",
          risk_indicators: %{"score" => 750},
          normalized_data: %{"bank_name" => "Test Bank"}
        })

      result = ProviderSummary.to_map(summary)

      assert result == %{
               "provider_status" => "active",
               "risk_indicators" => %{"score" => 750},
               "normalized_data" => %{"bank_name" => "Test Bank"}
             }
    end
  end
end
