defmodule DebtStalker.Applications.CursorPaginationTest do
  @moduledoc """
  Edge case tests for cursor-based pagination including invalid cursors,
  empty result sets, and boundary conditions.
  """
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "invalid cursor handling" do
    test "invalid base64 cursor is gracefully ignored" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)
      result = Applications.list_applications(%{cursor: "not-valid-base64!!!"})
      assert is_list(result.entries)
      assert result.entries != []
    end

    test "valid base64 but invalid JSON cursor is gracefully ignored" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)
      cursor = Base.url_encode64("not json at all")
      result = Applications.list_applications(%{cursor: cursor})
      assert is_list(result.entries)
      assert result.entries != []
    end

    test "valid JSON but missing fields cursor is gracefully ignored" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)
      cursor = Base.url_encode64(Jason.encode!(%{foo: "bar"}))
      result = Applications.list_applications(%{cursor: cursor})
      assert is_list(result.entries)
    end

    test "empty string cursor is gracefully handled" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)
      result = Applications.list_applications(%{cursor: ""})
      assert is_list(result.entries)
    end
  end

  describe "empty result set" do
    test "returns empty list with no applications matching filter" do
      result = Applications.list_applications(%{country: "ZZ"})
      assert result.entries == []
      assert result.cursor == nil
    end
  end

  describe "pagination correctness" do
    test "cursor advances through pages without duplicates" do
      # Create 5 applications
      apps =
        for i <- 1..5 do
          {:ok, app} =
            Applications.create_application(Map.put(@valid_es_attrs, :full_name, "User #{i}"))

          app
        end

      assert length(apps) == 5

      # Fetch first page (limit 2)
      page1 = Applications.list_applications(%{limit: 2})
      assert length(page1.entries) == 2
      assert page1.cursor != nil

      # Fetch second page
      page2 = Applications.list_applications(%{limit: 2, cursor: page1.cursor})
      assert length(page2.entries) == 2
      assert page2.cursor != nil

      # Fetch third page
      page3 = Applications.list_applications(%{limit: 2, cursor: page2.cursor})
      assert length(page3.entries) == 1
      assert page3.cursor == nil

      # Verify no duplicates across pages
      all_ids =
        (page1.entries ++ page2.entries ++ page3.entries)
        |> Enum.map(& &1.id)

      assert length(all_ids) == length(Enum.uniq(all_ids))
    end

    test "limit defaults to 20" do
      result = Applications.list_applications(%{})
      # Just verify it doesn't crash with default limit
      assert is_list(result.entries)
    end
  end
end
