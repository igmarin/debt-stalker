defmodule DebtStalker.Providers.MXAdapterTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.MXAdapter
  alias DebtStalker.Providers.ProviderSummary

  describe "fetch/2" do
    test "returns normalized summary for valid document" do
      params = %{identity_document: "GARC850101HDFRRL09"}
      assert {:ok, %ProviderSummary{} = summary} = MXAdapter.fetch("MX", params)
      assert summary.provider_status == "active"
      assert is_integer(summary.risk_indicators["buro_score"])
      assert summary.risk_indicators["buro_score"] >= 600
      assert is_binary(summary.risk_indicators["existing_debt"])
      assert summary.risk_indicators["payment_history"] in ["good", "mixed"]
      assert summary.normalized_data["institution"] == "Bureau de Credito MX"
    end

    test "returns deterministic results for same document" do
      params = %{identity_document: "GARC850101HDFRRL09"}
      {:ok, summary1} = MXAdapter.fetch("MX", params)
      {:ok, summary2} = MXAdapter.fetch("MX", params)
      assert summary1 == summary2
    end

    test "returns :unavailable for document starting with XXXX" do
      params = %{identity_document: "XXXX850101HDFRRL09"}
      assert {:error, :unavailable} = MXAdapter.fetch("MX", params)
    end

    test "returns :timeout for document starting with ZZZZ" do
      params = %{identity_document: "ZZZZ850101HDFRRL09"}
      assert {:error, :timeout} = MXAdapter.fetch("MX", params)
    end

    test "no raw payload in successful response" do
      params = %{identity_document: "GARC850101HDFRRL09"}
      {:ok, summary} = MXAdapter.fetch("MX", params)
      map = ProviderSummary.to_map(summary)
      refute Map.has_key?(map, "raw_payload")
      refute Map.has_key?(map, "raw")
    end
  end
end
