defmodule DebtStalkerWeb.ApplicationCreateLiveTest do
  use DebtStalkerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "ApplicationCreateLive" do
    test "renders create form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/applications/new")
      assert html =~ "New Credit Application"
      assert html =~ "Country"
      assert html =~ "Full Name"
    end

    test "shows country-specific document hint when country is selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/applications/new")

      html =
        view
        |> form("#create-form", %{"application" => %{"country" => "ES"}})
        |> render_change()

      assert html =~ "DNI"

      html =
        view
        |> form("#create-form", %{"application" => %{"country" => "MX"}})
        |> render_change()

      assert html =~ "CURP"
    end

    test "creates application and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/applications/new")

      view
      |> form("#create-form", %{
        "application" => %{
          "country" => "ES",
          "full_name" => "Juan Garcia",
          "identity_document" => "12345678Z",
          "requested_amount" => "5000",
          "monthly_income" => "2000"
        }
      })
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/applications/"
      assert flash["info"] =~ "created"
    end

    test "shows errors for invalid document", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/applications/new")

      html =
        view
        |> form("#create-form", %{
          "application" => %{
            "country" => "ES",
            "full_name" => "Test",
            "identity_document" => "INVALID",
            "requested_amount" => "5000",
            "monthly_income" => "2000"
          }
        })
        |> render_submit()

      assert html =~ "invalid DNI"
    end
  end
end
