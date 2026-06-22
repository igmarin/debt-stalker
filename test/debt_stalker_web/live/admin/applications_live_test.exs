defmodule DebtStalkerWeb.Admin.ApplicationsLiveTest do
  use DebtStalkerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias DebtStalker.Applications
  alias DebtStalker.Countries

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "Admin.ApplicationsLive" do
    test "renders application list with full name", %{conn: conn} do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications")
      assert html =~ "Solicitudes"
      assert html =~ "Juan Garcia"
      assert html =~ "****678Z"
    end

    test "formats amounts with currency symbol and thousand separators", %{conn: conn} do
      {:ok, _} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("12000"),
          monthly_income: Decimal.new("3000")
        })

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications")
      assert html =~ "$12,000"
    end

    test "filters by country via URL", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, _} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html = render_patch(view, ~p"/admin/applications?country=ES")

      assert html =~ "Juan Garcia"
      refute html =~ "Maria Lopez"
    end

    test "filters by country via form without blanking results", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html =
        view
        |> form("#admin-filter-form", %{
          "country" => "ES",
          "status" => "",
          "date_from" => "",
          "date_to" => ""
        })
        |> render_change()

      assert html =~ "Juan Garcia"
      refute html =~ "No se encontraron solicitudes"
    end

    test "filters by status", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html = render_patch(view, ~p"/admin/applications?status=pending_risk")
      assert html =~ "Juan Garcia"

      html = render_patch(view, ~p"/admin/applications?status=approved")
      refute html =~ "Juan Garcia"
    end

    test "shows empty state when filters match nothing", %{conn: conn} do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html = render_patch(view, ~p"/admin/applications?country=MX")
      assert html =~ "No se encontraron solicitudes"
    end

    test "sorts by amount when header is clicked", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, _} =
        Applications.create_application(%{
          @valid_es_attrs
          | full_name: "High Amount",
            identity_document: "87654321X",
            requested_amount: Decimal.new("9000")
        })

      {:ok, view, html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      # Default sort is application_date desc — both apps visible
      assert html =~ "Juan Garcia"
      assert html =~ "High Amount"

      html =
        view
        |> element("button[phx-value-field='requested_amount']")
        |> render_click()

      # After sorting by amount desc, the higher amount should appear first
      assert html =~ ~r/€9,000.*€5,000/s
    end

    test "sorts by full name when header is clicked", %{conn: conn} do
      {:ok, _} =
        Applications.create_application(%{
          @valid_es_attrs
          | full_name: "Zebra Applicant",
            identity_document: "87654321X"
        })

      {:ok, _} =
        Applications.create_application(%{
          @valid_es_attrs
          | full_name: "Alpha Applicant",
            identity_document: Countries.random_identity_document("ES")
        })

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html =
        view
        |> element("button[phx-value-field='full_name']")
        |> render_click()

      assert html =~ ~r/Zebra Applicant.*Alpha Applicant/s
    end

    test "paginates with page controls", %{conn: conn} do
      for i <- 1..25 do
        {:ok, _} =
          Applications.create_application(%{
            @valid_es_attrs
            | full_name: "Applicant #{i}",
              identity_document: Countries.random_identity_document("ES")
          })
      end

      {:ok, view, html} = live(with_role(conn, "admin"), ~p"/admin/applications?per_page=10")
      assert html =~ "Mostrando"
      assert html =~ "1–10"
      assert html =~ "25"

      # Navigate to page 2
      html = render_click(view, "paginate", %{"page" => "2"})
      assert html =~ "Applicant"
    end

    test "updates in real-time via PubSub", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      Phoenix.PubSub.broadcast(DebtStalker.PubSub, "applications:list", {:status_changed, %{}})

      html = render(view)
      assert html =~ "Riesgo pendiente"
    end

    test "highlights updated rows in real time", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      send(
        view.pid,
        {:status_changed, %{application_id: app.id, from: "submitted", to: "pending_risk"}}
      )

      html = render(view)
      assert html =~ "bg-primary/15"

      send(view.pid, {:clear_highlight, app.id})

      html = render(view)
      refute html =~ "bg-primary/15"
    end
  end
end
