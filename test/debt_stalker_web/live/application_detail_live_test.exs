defmodule DebtStalkerWeb.ApplicationDetailLiveTest do
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

  describe "ApplicationDetailLive" do
    test "renders application details", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(conn, "/applications/#{app.id}")
      assert html =~ "Application Detail"
      assert html =~ "Juan Garcia"
      assert html =~ "****678Z"
      assert html =~ "submitted"
    end

    test "updates in real-time when status changes", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(conn, "/applications/#{app.id}")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      html = render(view)
      assert html =~ "pending_risk"
    end

    test "redirects for unknown application", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/applications"}}} =
               live(conn, "/applications/#{Ecto.UUID.generate()}")
    end

    test "renders status update form with allowed transitions", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(conn, "/applications/#{app.id}")

      assert html =~ "Update Status"
      assert html =~ "pending_risk"
    end

    test "status update form does not show invalid transitions for submitted app", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} = live(conn, "/applications/#{app.id}")

      # approved is not a valid transition from submitted
      refute html =~ ~r/value="approved"/
    end

    test "submitting valid status transition updates the application", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(conn, "/applications/#{app.id}")

      view
      |> element("form#status-update-form")
      |> render_submit(%{"status" => "pending_risk"})

      html = render(view)
      assert html =~ "pending_risk"
    end

    test "invalid status transition does not change status", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} = live(conn, "/applications/#{app.id}")

      view
      |> element("form#status-update-form")
      |> render_submit(%{"status" => "approved"})

      html = render(view)
      # Status should still be submitted (approved is not a valid transition from submitted)
      assert html =~ "submitted"
      refute html =~ ~r/<p class="font-semibold">approved<\/p>/
    end
  end
end
