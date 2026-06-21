defmodule DebtStalker.Countries.RegistryTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Countries.Registry

  describe "lookup/1" do
    test "resolves ES to the ES country module" do
      assert {:ok, DebtStalker.Countries.ES} = Registry.lookup("ES")
    end

    test "resolves MX to the MX country module" do
      assert {:ok, DebtStalker.Countries.MX} = Registry.lookup("MX")
    end

    test "returns error for unsupported country" do
      assert {:error, :unsupported_country} = Registry.lookup("XX")
    end

    test "returns error for empty string" do
      assert {:error, :unsupported_country} = Registry.lookup("")
    end

    test "is case-sensitive (lowercase fails)" do
      assert {:error, :unsupported_country} = Registry.lookup("es")
    end
  end

  describe "supported_countries/0" do
    test "returns sorted list of supported country codes" do
      countries = Registry.supported_countries()
      assert "ES" in countries
      assert "MX" in countries
      assert countries == Enum.sort(countries)
    end
  end
end
