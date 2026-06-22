defmodule DebtStalkerWeb.Admin.ApplicationDetailLiveTest do
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

  describe "Admin.ApplicationDetailLive" do
    test "redirects applicants to the admin login page", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      assert {:error, {:redirect, %{to: "/admin/login"}}} =
               live(with_role(conn, "applicant"), ~p"/admin/applications/#{app.id}")
    end

    test "renders application details", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")
      assert html =~ app.id
      assert html =~ "Juan Garcia"
      assert html =~ "****678Z"
      assert html =~ "Enviada"
    end

    test "updates in real-time when status changes", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      html = render(view)
      assert html =~ "Riesgo pendiente"
    end

    test "redirects for unknown application", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/applications"}}} =
               live(with_role(conn, "admin"), ~p"/admin/applications/#{Ecto.UUID.generate()}")
    end

    test "renders status update form with allowed transitions", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")

      assert html =~ "Actualizar estado"
      assert html =~ "Riesgo pendiente"
    end

    test "status update form does not show invalid transitions for submitted app", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")

      refute html =~ ~r/value="approved"/
    end

    test "submitting valid status transition updates the application", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")

      view
      |> element("form#status-update-form")
      |> render_submit(%{"status" => "pending_risk"})

      html = render(view)
      assert html =~ "Riesgo pendiente"
    end

    test "invalid status transition does not change status", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(with_role(conn, "admin"), ~p"/admin/applications/#{app.id}")

      view
      |> element("form#status-update-form")
      |> render_submit(%{"status" => "approved"})

      html = render(view)
      assert html =~ "Enviada"
      refute html =~ "Aprobada"
    end
  end
end
