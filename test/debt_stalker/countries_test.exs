defmodule DebtStalker.CountriesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias DebtStalker.Countries

  describe "get_document_hint/1" do
    test "returns the country-specific hint for supported countries" do
      assert Countries.get_document_hint("ES") =~ "DNI"
      assert Countries.get_document_hint("MX") =~ "CURP"
    end

    test "returns an empty string for unknown countries" do
      assert Countries.get_document_hint("") == ""
      assert Countries.get_document_hint("XX") == ""
    end
  end
end
