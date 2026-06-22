defmodule DebtStalkerWeb.Apply.ApplicationFormLiveTest do
  use DebtStalkerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "Apply.ApplicationFormLive" do
    test "renders the applicant form", %{conn: conn} do
      {:ok, _view, html} = live(with_role(conn, "applicant"), ~p"/apply")
      assert html =~ "Apply for credit"
      assert html =~ "Country"
      assert html =~ "Full name"
    end

    test "redirects to landing when no role is set", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/apply")
    end

    test "shows country-specific document hint when country is selected", %{conn: conn} do
      {:ok, view, _html} = live(with_role(conn, "applicant"), ~p"/apply")

      html =
        view
        |> form("#apply-form", %{"application" => %{"country" => "ES"}})
        |> render_change()

      assert html =~ "DNI"

      html =
        view
        |> form("#apply-form", %{"application" => %{"country" => "MX"}})
        |> render_change()

      assert html =~ "CURP"
    end

    test "shows inline validation errors on change", %{conn: conn} do
      {:ok, view, _html} = live(with_role(conn, "applicant"), ~p"/apply")

      html =
        view
        |> form("#apply-form", %{
          "application" => %{
            "country" => "ES",
            "full_name" => "",
            "identity_document" => "",
            "requested_amount" => "",
            "monthly_income" => ""
          }
        })
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "initializes document hint from mount params", %{conn: conn} do
      {:ok, _view, html} = live(with_role(conn, "applicant"), ~p"/apply?application[country]=ES")
      assert html =~ "DNI"
    end

    test "keeps document hint after submission error", %{conn: conn} do
      {:ok, view, _html} = live(with_role(conn, "applicant"), ~p"/apply")

      view
      |> form("#apply-form", %{"application" => %{"country" => "ES"}})
      |> render_change()

      html =
        view
        |> form("#apply-form", %{
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
      assert html =~ "DNI"
    end

    test "creates application and redirects to confirmation", %{conn: conn} do
      {:ok, view, _html} = live(with_role(conn, "applicant"), ~p"/apply")

      view
      |> form("#apply-form", %{
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
      assert path =~ "/apply/"
      assert path =~ "/confirmation"
      assert flash["info"] =~ "submitted"
    end

    test "shows errors for invalid document", %{conn: conn} do
      {:ok, view, _html} = live(with_role(conn, "applicant"), ~p"/apply")

      html =
        view
        |> form("#apply-form", %{
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
