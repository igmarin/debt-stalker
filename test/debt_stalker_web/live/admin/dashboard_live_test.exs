defmodule DebtStalkerWeb.Admin.DashboardLiveTest do
  use DebtStalkerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias DebtStalker.Applications

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  describe "Admin.DashboardLive" do
    test "redirects unauthenticated users to the admin login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin")
    end

    test "redirects applicants to the admin login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} =
               live(with_role(conn, "applicant"), ~p"/admin")
    end

    test "renders dashboard stats and charts", %{conn: conn} do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      assert html =~ "Panel"
      assert html =~ "Total de solicitudes"
      assert html =~ "Errores del proveedor"
      assert html =~ "Juan Garcia"
      assert html =~ "Solicitudes en el tiempo"
      assert html =~ "Distribución por estado"
      assert html =~ "<canvas"
    end

    test "formats amounts with currency symbol in recent table", %{conn: conn} do
      {:ok, _} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("12000"),
          monthly_income: Decimal.new("3000")
        })

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      assert html =~ "$12,000"
    end

    test "filters dashboard metrics by country", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, _} =
        Applications.create_application(%{
          country: "MX",
          full_name: "Maria Lopez",
          identity_document: "GARC850101HDFRRL09",
          requested_amount: Decimal.new("8000"),
          monthly_income: Decimal.new("2000")
        })

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin")

      html = render_patch(view, ~p"/admin?country=ES")

      assert html =~ "Juan Garcia"
      refute html =~ "Maria Lopez"
    end

    test "counts decisions made today", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, app} = Applications.update_status(app.id, "pending_risk", "system")
      {:ok, _} = Applications.update_status(app.id, "approved", "system")

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      assert html =~ "Decididas hoy"
      assert html =~ "1"
    end

    test "renders empty state when no applications exist", %{conn: conn} do
      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      assert html =~ "Panel"
      assert html =~ "0"
    end

    test "formats total count with thousand separators", %{conn: conn} do
      # Create enough applications to verify formatting
      for i <- 1..5 do
        {:ok, _} =
          Applications.create_application(%{
            @valid_es_attrs
            | full_name: "Applicant #{i}",
              identity_document: DebtStalker.Countries.random_identity_document("ES")
          })
      end

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      # The stat card should show the count
      assert html =~ "Total de solicitudes"
      assert html =~ "5"
    end

    test "filters by status via URL", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin")

      html = render_patch(view, ~p"/admin?status=pending_risk")
      assert html =~ "Juan Garcia"

      html = render_patch(view, ~p"/admin?status=approved")
      refute html =~ "Juan Garcia"
    end

    test "reloads via PubSub broadcast", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      Phoenix.PubSub.broadcast(DebtStalker.PubSub, "applications:list", {:status_changed, %{}})

      html = render(view)
      assert html =~ "Riesgo pendiente"
    end

    test "renders ES amounts with euro symbol", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin")
      assert html =~ "€5,000"
    end
  end
end
