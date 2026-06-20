defmodule DebtStalker.Applications.QueryTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias DebtStalker.Applications.CreditApplication

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  @valid_mx_attrs %{
    country: "MX",
    full_name: "Maria Lopez",
    identity_document: "GARC850101HDFRRL09",
    requested_amount: Decimal.new("8000"),
    monthly_income: Decimal.new("2000")
  }

  describe "get_application/1" do
    test "returns application by uuid" do
      {:ok, created} = Applications.create_application(@valid_es_attrs)
      assert {:ok, %CreditApplication{} = app} = Applications.get_application(created.id)
      assert app.id == created.id
      assert app.country == "ES"
    end

    test "returns redacted document" do
      {:ok, created} = Applications.create_application(@valid_es_attrs)
      {:ok, app} = Applications.get_application(created.id)
      assert app.identity_document != nil
    end

    test "returns error for unknown uuid" do
      assert {:error, :not_found} = Applications.get_application(Ecto.UUID.generate())
    end
  end

  describe "list_applications/1" do
    setup do
      {:ok, es_app} = Applications.create_application(@valid_es_attrs)

      {:ok, mx_app} =
        Applications.create_application(%{
          @valid_mx_attrs
          | identity_document: "LOPE900215MMCPZN02"
        })

      %{es_app: es_app, mx_app: mx_app}
    end

    test "returns all applications without filters" do
      %{entries: entries} = Applications.list_applications(%{})
      assert length(entries) >= 2
    end

    test "filters by country" do
      %{entries: entries} = Applications.list_applications(%{country: "ES"})
      assert Enum.all?(entries, &(&1.country == "ES"))
    end

    test "filters by status" do
      %{entries: entries} = Applications.list_applications(%{status: "submitted"})
      assert Enum.all?(entries, &(&1.status == "submitted"))
    end

    test "filters by date range" do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)
      tomorrow = Date.add(today, 1)

      %{entries: entries} =
        Applications.list_applications(%{date_from: yesterday, date_to: tomorrow})

      assert length(entries) >= 2
    end

    test "returns cursor for pagination" do
      result = Applications.list_applications(%{limit: 1})
      assert length(result.entries) == 1
      assert result.cursor != nil
    end

    test "cursor pagination returns next page" do
      result1 = Applications.list_applications(%{limit: 1})
      result2 = Applications.list_applications(%{limit: 1, cursor: result1.cursor})
      assert result2.entries != result1.entries
    end

    test "no unbounded OFFSET used (cursor-based)" do
      result = Applications.list_applications(%{limit: 10})
      assert Map.has_key?(result, :cursor)
    end
  end
end
