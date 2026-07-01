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
      assert Countries.get_document_hint("CO") =~ "Cédula"
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

      assert DebtStalker.Countries.CO.validate_document(Countries.random_identity_document("CO")) ==
               :ok
    end

    test "returns nil for unknown countries" do
      assert Countries.random_identity_document("XX") == nil
    end
  end

  describe "currency_symbol/1" do
    test "returns the correct symbol for supported countries" do
      assert Countries.currency_symbol("ES") == "€"
      assert Countries.currency_symbol("MX") == "$"
      assert Countries.currency_symbol("CO") == "$"
    end

    test "returns an empty string for unknown or nil countries" do
      assert Countries.currency_symbol("XX") == ""
      assert Countries.currency_symbol(nil) == ""
    end
  end
end
