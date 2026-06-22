defmodule DebtStalkerWeb.Apply.ApplicationConfirmationLiveTest do
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

  describe "Apply.ApplicationConfirmationLive" do
    test "renders confirmation and tracker", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, _view, html} =
        live(with_role(conn, "applicant"), ~p"/apply/#{app.id}/confirmation")

      assert html =~ "Application received"
      assert html =~ app.id
      assert html =~ "Juan Garcia"
      assert html =~ "Submitted"
    end

    test "updates status badge in real time", %{conn: conn} do
      {:ok, app} = Applications.create_application(@valid_es_attrs)

      {:ok, view, _html} =
        live(with_role(conn, "applicant"), ~p"/apply/#{app.id}/confirmation")

      {:ok, _} = Applications.update_status(app.id, "pending_risk", "system")

      html = render(view)
      assert html =~ "Pending risk"
    end

    test "redirects for unknown application", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/apply"}}} =
               live(with_role(conn, "applicant"), ~p"/apply/#{Ecto.UUID.generate()}/confirmation")
    end
  end
end
