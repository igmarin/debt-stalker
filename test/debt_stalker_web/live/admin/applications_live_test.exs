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
    test "renders application list", %{conn: conn} do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications")
      assert html =~ "Solicitudes"
      assert html =~ "Juan G."
      refute html =~ "Juan Garcia"
      assert html =~ "****678Z"
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

      assert html =~ "Juan G."
      refute html =~ "Maria Lopez"
      refute html =~ "Maria L."
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

      assert html =~ "Juan G."
      refute html =~ "Juan Garcia"
      refute html =~ "No se encontraron solicitudes"
    end

    test "filters by status", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html = render_patch(view, ~p"/admin/applications?status=pending_risk")
      assert html =~ "Juan G."

      html = render_patch(view, ~p"/admin/applications?status=approved")
      refute html =~ "Juan G."
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

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      html =
        view
        |> element("button[phx-value-field='requested_amount']")
        |> render_click()

      assert html =~ "9000"
    end

    test "paginates with cursor controls", %{conn: conn} do
      for i <- 1..21 do
        {:ok, _} =
          Applications.create_application(%{
            @valid_es_attrs
            | full_name: "Applicant #{i}",
              identity_document: Countries.random_identity_document("ES")
          })
      end

      {:ok, view, html} = live(with_role(conn, "admin"), ~p"/admin/applications?limit=10")
      assert html =~ "Mostrando"
      assert html =~ "Cargar más"

      [cursor] = Regex.run(~r/phx-value-cursor=\"([^\"]+)\"/, html, capture: :all_but_first)
      html = render_click(view, "load_more", %{"cursor" => cursor})

      assert html =~ "Applicant"
    end

    test "ignores invalid cursor param without crashing", %{conn: conn} do
      {:ok, _} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      assert render_click(view, "load_more", %{"cursor" => "invalid"}) =~ "Juan G."
      assert render_patch(view, ~p"/admin/applications?cursor=invalid") =~ "Juan G."
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
