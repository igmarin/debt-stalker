defmodule DebtStalkerWeb.Admin.ApplicationsLiveTest do
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

  describe "Admin.ApplicationsLive" do
    test "renders application list", %{conn: conn} do
      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications")
      assert html =~ "Applications"
      assert html =~ "Juan Garcia"
      assert html =~ "****678Z"
    end

    test "filters by country", %{conn: conn} do
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
      assert html =~ "No applications found"
    end

    test "updates in real-time via PubSub", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)
      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")
      Phoenix.PubSub.broadcast(DebtStalker.PubSub, "applications:list", {:status_changed, %{}})

      html = render(view)
      assert html =~ "pending_risk"
    end
  end
end
