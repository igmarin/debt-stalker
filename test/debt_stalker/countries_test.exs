defmodule DebtStalker.CountriesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias DebtStalker.Countries

  setup do
    Application.ensure_all_started(:debt_stalker)
    :ok
  end

  describe "get_document_hint/1" do
    test "returns the country-specific hint for supported countries" do
      assert Countries.get_document_hint("ES") =~ "DNI"
      assert Countries.get_document_hint("MX") =~ "CURP"
    end

    test "returns an empty string for unknown or empty countries" do
      assert Countries.get_document_hint("") == ""
      assert Countries.get_document_hint("XX") == ""
      assert Countries.get_document_hint(nil) == ""
    end
  end

  describe "random_identity_document/1" do
    test "returns a valid document for supported countries" do
      assert DebtStalker.Countries.ES.validate_document(Countries.random_identity_document("ES")) ==
               :ok

      assert DebtStalker.Countries.MX.validate_document(Countries.random_identity_document("MX")) ==
               :ok
    end

    test "returns nil for unknown countries" do
      assert Countries.random_identity_document("XX") == nil
    end
  end
end
