defmodule DebtStalker.Providers.RegistryTest do
  use ExUnit.Case, async: true

  alias DebtStalker.Providers.Registry

  setup do
    # The registry is an ETS-backed GenServer started by the OTP application.
    # Ensure the app is running so the named table exists.
    Application.ensure_all_started(:debt_stalker)
    assert Process.whereis(Registry) != nil, "Providers.Registry must be running"
    :ok
  end

  describe "lookup/1" do
    test "resolves ES to ESAdapter" do
      assert {:ok, DebtStalker.Providers.ESAdapter} = Registry.lookup("ES")
    end

    test "resolves MX to MXAdapter" do
      assert {:ok, DebtStalker.Providers.MXAdapter} = Registry.lookup("MX")
    end

    test "resolves CO to COAdapter" do
      assert {:ok, DebtStalker.Providers.COAdapter} = Registry.lookup("CO")
    end

    test "returns error for unsupported country" do
      assert {:error, :unsupported_provider} = Registry.lookup("XX")
    end
  end

  describe "supported_providers/0" do
    test "returns sorted list of supported country codes" do
      assert Registry.supported_providers() == ["CO", "ES", "MX"]
    end
  end
end
