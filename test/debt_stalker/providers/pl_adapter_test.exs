defmodule DebtStalker.Providers.PLAdapterTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.PLAdapter
  alias DebtStalker.Providers.ProviderSummary

  describe "fetch/2" do
    test "returns normalized summary for valid document" do
      params = %{identity_document: "02070803628"}

      assert {:ok, %ProviderSummary{} = summary} = PLAdapter.fetch("PL", params)

      assert summary.provider_status == "active"
      assert is_integer(summary.risk_indicators["bik_score"])
      assert summary.risk_indicators["bik_score"] >= 650
      assert is_binary(summary.risk_indicators["existing_debt"])
      assert is_integer(summary.risk_indicators["active_loans"])
      assert summary.normalized_data["bank_name"] == "Bank Symulowany PL"
      assert is_binary(summary.normalized_data["monthly_payment"])
    end

    test "returns deterministic results for same document" do
      params = %{identity_document: "02070803628"}
      {:ok, summary1} = PLAdapter.fetch("PL", params)
      {:ok, summary2} = PLAdapter.fetch("PL", params)

      assert summary1 == summary2
    end

    test "returns :unavailable for document starting with 000" do
      params = %{identity_document: "00012345678"}
      assert {:error, :unavailable} = PLAdapter.fetch("PL", params)
    end

    test "returns :timeout for document starting with 999" do
      params = %{identity_document: "99912345678"}
      assert {:error, :timeout} = PLAdapter.fetch("PL", params)
    end

    test "no raw payload in successful response" do
      params = %{identity_document: "02070803628"}
      {:ok, summary} = PLAdapter.fetch("PL", params)
      map = ProviderSummary.to_map(summary)

      refute Map.has_key?(map, "raw_payload")
      refute Map.has_key?(map, "raw")
    end
  end
end
