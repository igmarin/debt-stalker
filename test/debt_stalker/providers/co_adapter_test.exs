defmodule DebtStalker.Providers.COAdapterTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.COAdapter
  alias DebtStalker.Providers.ProviderSummary

  describe "fetch/2" do
    test "returns normalized summary for valid document" do
      params = %{identity_document: "1234567890"}
      assert {:ok, %ProviderSummary{} = summary} = COAdapter.fetch("CO", params)
      assert summary.provider_status == "active"
      assert is_integer(summary.risk_indicators["datacredito_score"])
      assert summary.risk_indicators["datacredito_score"] >= 580
      assert is_integer(summary.risk_indicators["active_loans"])
      assert is_binary(summary.risk_indicators["existing_debt"])
      assert summary.risk_indicators["payment_history"] in ["good", "mixed"]
      assert summary.normalized_data["institution"] == "Datacredito CO"
    end

    test "returns deterministic results for same document" do
      params = %{identity_document: "1234567890"}
      {:ok, summary1} = COAdapter.fetch("CO", params)
      {:ok, summary2} = COAdapter.fetch("CO", params)
      assert summary1 == summary2
    end

    test "returns :unavailable for document starting with 00000000" do
      params = %{identity_document: "000000008"}
      assert {:error, :unavailable} = COAdapter.fetch("CO", params)
    end

    test "returns :timeout for document starting with 99999999" do
      params = %{identity_document: "999999999"}
      assert {:error, :timeout} = COAdapter.fetch("CO", params)
    end

    test "no raw payload in successful response" do
      params = %{identity_document: "1234567890"}
      {:ok, summary} = COAdapter.fetch("CO", params)
      map = ProviderSummary.to_map(summary)
      refute Map.has_key?(map, "raw_payload")
      refute Map.has_key?(map, "raw")
    end
  end
end
