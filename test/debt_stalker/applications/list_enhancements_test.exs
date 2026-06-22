defmodule DebtStalker.Applications.ListEnhancementsTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications
  alias DebtStalker.Countries

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "filter normalization" do
    test "empty country string does not filter out all results" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      %{entries: entries} = Applications.list_applications(%{country: ""})
      assert entries != []
    end

    test "empty status string does not filter out all results" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      %{entries: entries} = Applications.list_applications(%{status: ""})
      assert entries != []
    end
  end

  describe "page pagination" do
    setup do
      for i <- 1..25 do
        {:ok, _} =
          Applications.create_application(%{
            @valid_es_attrs
            | full_name: "Applicant #{String.pad_leading("#{i}", 2, "0")}",
              identity_document: Countries.random_identity_document("ES")
          })
      end

      :ok
    end

    test "returns page metadata" do
      result = Applications.list_applications(%{page: 1, per_page: 10})

      assert length(result.entries) == 10
      assert result.page == 1
      assert result.per_page == 10
      assert result.total_count >= 25
      assert result.total_pages >= 3
      assert result.cursor == nil
    end

    test "page 2 returns different entries" do
      page1 =
        Applications.list_applications(%{
          page: 1,
          per_page: 10,
          sort_by: "full_name",
          sort_dir: "asc"
        })

      page2 =
        Applications.list_applications(%{
          page: 2,
          per_page: 10,
          sort_by: "full_name",
          sort_dir: "asc"
        })

      refute page1.entries == page2.entries
    end

    test "respects filters with page pagination" do
      {:ok, _} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      result = Applications.list_applications(%{country: "ES", page: 1, per_page: 50})

      assert Enum.all?(result.entries, &(&1.country == "ES"))
      refute Enum.any?(result.entries, &(&1.full_name == "Maria Lopez"))
    end
  end

  describe "sorting" do
    setup do
      {:ok, low} =
        Applications.create_application(%{
          @valid_es_attrs
          | requested_amount: Decimal.new("1000")
        })

      {:ok, high} =
        Applications.create_application(%{
          @valid_es_attrs
          | full_name: "High Amount",
            identity_document: "87654321X",
            requested_amount: Decimal.new("9000")
        })

      %{low: low, high: high}
    end

    test "sorts requested amount ascending" do
      %{entries: entries} =
        Applications.list_applications(%{
          page: 1,
          per_page: 10,
          sort_by: "requested_amount",
          sort_dir: "asc"
        })

      amounts = Enum.map(entries, &Decimal.to_float(&1.requested_amount))
      assert amounts == Enum.sort(amounts)
    end

    test "sorts requested amount descending" do
      %{entries: entries} =
        Applications.list_applications(%{
          page: 1,
          per_page: 10,
          sort_by: "requested_amount",
          sort_dir: "desc"
        })

      amounts = Enum.map(entries, &Decimal.to_float(&1.requested_amount))
      assert amounts == Enum.sort(amounts, :desc)
    end
  end

  describe "dashboard_analytics/1" do
    test "returns filtered breakdowns" do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      analytics = Applications.dashboard_analytics(%{country: "ES"})

      assert analytics.stats.total >= 1
      assert is_list(analytics.status_breakdown)
      assert is_list(analytics.by_country)
      assert is_list(analytics.timeline)
      refute Enum.any?(analytics.by_country, &(&1.country == "MX"))
    end

    test "derives KPI stats from status breakdown instead of separate count queries" do
      {:ok, es_app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(es_app.id, "pending_risk", "system")

      {:ok, mx_app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      {:ok, _} = Applications.update_status(mx_app.id, "pending_risk", "system")

      stats = Applications.dashboard_stats(%{country: "ES"})

      assert stats.total == stats.pending_risk
      assert stats.pending_risk >= 1
      assert stats.additional_review == 0
      assert stats.provider_errors == 0
    end
  end

  describe "count_decided_today/1" do
    test "respects country filter" do
      {:ok, es_app} = Applications.create_application(@valid_es_attrs)
      {:ok, es_app} = Applications.update_status(es_app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(es_app.id, "approved", "system")

      {:ok, mx_app} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      {:ok, mx_app} = Applications.update_status(mx_app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(mx_app.id, "approved", "system")

      assert Applications.count_decided_today(%{country: "ES"}) == 1
      assert Applications.count_decided_today(%{country: "MX"}) == 1
      assert Applications.count_decided_today(%{}) == 2
    end
  end
end
