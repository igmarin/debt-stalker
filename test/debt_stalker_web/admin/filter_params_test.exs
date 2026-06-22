defmodule DebtStalkerWeb.Admin.FilterParamsTest do
  use ExUnit.Case, async: true

  alias DebtStalkerWeb.Admin.FilterParams

  describe "from_params/1" do
    test "parses all valid params" do
      params = %{
        "country" => "ES",
        "status" => "pending_risk",
        "date_from" => "2026-01-01",
        "date_to" => "2026-06-30",
        "sort_by" => "full_name",
        "sort_dir" => "asc",
        "cursor" => "abc123",
        "limit" => "10",
        "page" => "2",
        "per_page" => "20"
      }

      result = FilterParams.from_params(params)

      assert result.country == "ES"
      assert result.status == "pending_risk"
      assert result.date_from == ~D[2026-01-01]
      assert result.date_to == ~D[2026-06-30]
      assert result.sort_by == "full_name"
      assert result.sort_dir == "asc"
      assert result.cursor == "abc123"
      assert result.limit == 10
      assert result.page == 2
      assert result.per_page == 20
    end

    test "returns empty map for empty params" do
      assert FilterParams.from_params(%{}) == %{}
    end

    test "converts blank strings to nil and drops them" do
      params = %{"country" => "", "status" => "  ", "date_from" => ""}

      result = FilterParams.from_params(params)

      refute Map.has_key?(result, :country)
      refute Map.has_key?(result, :status)
      refute Map.has_key?(result, :date_from)
    end

    test "rejects invalid sort_by field" do
      result = FilterParams.from_params(%{"sort_by" => "invalid_field"})
      refute Map.has_key?(result, :sort_by)
    end

    test "rejects invalid sort_dir" do
      result = FilterParams.from_params(%{"sort_dir" => "sideways"})
      refute Map.has_key?(result, :sort_dir)
    end

    test "rejects invalid date format" do
      result = FilterParams.from_params(%{"date_from" => "not-a-date"})
      refute Map.has_key?(result, :date_from)
    end

    test "rejects non-positive integers for limit/page/per_page" do
      result = FilterParams.from_params(%{"limit" => "0", "page" => "-1", "per_page" => "abc"})
      refute Map.has_key?(result, :limit)
      refute Map.has_key?(result, :page)
      refute Map.has_key?(result, :per_page)
    end

    test "passes through Date structs for date_from/date_to" do
      result = FilterParams.from_params(%{"date_from" => ~D[2026-03-15]})
      assert result.date_from == ~D[2026-03-15]
    end

    test "handles non-string values gracefully" do
      result = FilterParams.from_params(%{"country" => 123})
      assert result.country == 123
    end
  end

  describe "to_query/1" do
    test "serializes all filter keys to string keys" do
      filters = %{
        country: "ES",
        status: "approved",
        date_from: ~D[2026-01-01],
        date_to: ~D[2026-06-30],
        sort_by: "full_name",
        sort_dir: "asc",
        cursor: "abc",
        limit: 10,
        page: 2,
        per_page: 20
      }

      query = FilterParams.to_query(filters)

      assert query["country"] == "ES"
      assert query["status"] == "approved"
      assert query["date_from"] == "2026-01-01"
      assert query["date_to"] == "2026-06-30"
      assert query["sort_by"] == "full_name"
      assert query["sort_dir"] == "asc"
      assert query["cursor"] == "abc"
      assert query["limit"] == "10"
      assert query["page"] == "2"
      assert query["per_page"] == "20"
    end

    test "omits nil and empty values" do
      query = FilterParams.to_query(%{country: nil, status: "", sort_by: "full_name"})

      refute Map.has_key?(query, "country")
      refute Map.has_key?(query, "status")
      assert query["sort_by"] == "full_name"
    end

    test "handles empty filter map" do
      assert FilterParams.to_query(%{}) == %{}
    end

    test "handles string date values" do
      query = FilterParams.to_query(%{date_from: "2026-01-01"})
      assert query["date_from"] == "2026-01-01"
    end
  end

  describe "toggle_sort/2" do
    test "sets sort_by and defaults to desc for new field" do
      result = FilterParams.toggle_sort(%{}, "full_name")
      assert result.sort_by == "full_name"
      assert result.sort_dir == "desc"
    end

    test "toggles from desc to asc when same field is clicked again" do
      filters = %{sort_by: "full_name", sort_dir: "desc"}
      result = FilterParams.toggle_sort(filters, "full_name")
      assert result.sort_dir == "asc"
    end

    test "resets to desc when switching to a different field" do
      filters = %{sort_by: "full_name", sort_dir: "asc"}
      result = FilterParams.toggle_sort(filters, "requested_amount")
      assert result.sort_by == "requested_amount"
      assert result.sort_dir == "desc"
    end

    test "removes cursor and page on sort change" do
      filters = %{sort_by: "full_name", sort_dir: "asc", cursor: "abc", page: 3}
      result = FilterParams.toggle_sort(filters, "requested_amount")
      refute Map.has_key?(result, :cursor)
      refute Map.has_key?(result, :page)
    end

    test "ignores invalid sort field" do
      filters = %{sort_by: "full_name", sort_dir: "asc"}
      result = FilterParams.toggle_sort(filters, "invalid_field")
      assert result.sort_by == "full_name"
      assert result.sort_dir == "asc"
    end

    test "uses default sort_by when not present in filters" do
      result = FilterParams.toggle_sort(%{}, "application_date")
      assert result.sort_dir == "asc"
    end
  end

  describe "format_date_for_input/1" do
    test "formats a Date to ISO 8601" do
      assert FilterParams.format_date_for_input(~D[2026-03-15]) == "2026-03-15"
    end

    test "returns nil for nil input" do
      assert FilterParams.format_date_for_input(nil) == nil
    end
  end

  describe "allowed_sort_fields/0" do
    test "returns the list of allowed sort fields" do
      fields = FilterParams.allowed_sort_fields()
      assert "application_date" in fields
      assert "full_name" in fields
      assert "requested_amount" in fields
      assert "country" in fields
      assert "status" in fields
    end
  end
end
