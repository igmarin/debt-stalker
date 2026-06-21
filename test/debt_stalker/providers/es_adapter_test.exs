defmodule DebtStalker.Providers.ESAdapterTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.ESAdapter
  alias DebtStalker.Providers.ProviderSummary

  describe "fetch/2" do
    test "returns normalized summary for valid document" do
      params = %{identity_document: "12345678Z"}
      assert {:ok, %ProviderSummary{} = summary} = ESAdapter.fetch("ES", params)
      assert summary.provider_status == "active"
      assert is_integer(summary.risk_indicators["credit_score"])
      assert summary.risk_indicators["credit_score"] >= 700
      assert is_integer(summary.risk_indicators["active_loans"])
      assert summary.normalized_data["bank_name"] == "Banco Simulado ES"
      assert is_binary(summary.normalized_data["monthly_payment"])
    end

    test "returns deterministic results for same document" do
      params = %{identity_document: "12345678Z"}
      {:ok, summary1} = ESAdapter.fetch("ES", params)
      {:ok, summary2} = ESAdapter.fetch("ES", params)
      assert summary1 == summary2
    end

    test "returns :unavailable for document starting with 00000000" do
      params = %{identity_document: "00000000T"}
      assert {:error, :unavailable} = ESAdapter.fetch("ES", params)
    end

    test "returns :timeout for document starting with 99999999" do
      params = %{identity_document: "99999999R"}
      assert {:error, :timeout} = ESAdapter.fetch("ES", params)
    end

    test "no raw payload in successful response" do
      params = %{identity_document: "12345678Z"}
      {:ok, summary} = ESAdapter.fetch("ES", params)
      map = ProviderSummary.to_map(summary)
      refute Map.has_key?(map, "raw_payload")
      refute Map.has_key?(map, "raw")
    end
  end
end
