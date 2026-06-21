defmodule DebtStalkerWeb.Api.ApplicationControllerEdgeTest do
  @moduledoc """
  Edge case tests for the Application API controller including
  invalid numeric input, boundary values, and error handling.
  """
  use DebtStalkerWeb.ConnCase, async: false

  alias DebtStalkerWeb.Auth.Token

  defp auth_conn(conn, role) do
    {:ok, token} = Token.generate_token(role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/applications with invalid numeric input" do
    test "non-numeric requested_amount returns 422", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test User",
          "identity_document" => "12345678Z",
          "requested_amount" => "abc",
          "monthly_income" => "2000"
        })

      assert json_response(conn, 422)
    end

    test "non-numeric monthly_income returns 422", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test User",
          "identity_document" => "12345678Z",
          "requested_amount" => "5000",
          "monthly_income" => "not_a_number"
        })

      assert json_response(conn, 422)
    end

    test "empty string amounts return 422", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test User",
          "identity_document" => "12345678Z",
          "requested_amount" => "",
          "monthly_income" => ""
        })

      assert json_response(conn, 422)
    end

    test "very large amount is accepted", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test User",
          "identity_document" => "12345678Z",
          "requested_amount" => "99999999",
          "monthly_income" => "50000"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["requested_amount"] == "99999999"
    end

    test "decimal amounts are handled correctly", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test User",
          "identity_document" => "12345678Z",
          "requested_amount" => "5000.50",
          "monthly_income" => "2000.75"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["status"] == "submitted"
    end
  end

  describe "GET /api/applications/:id edge cases" do
    test "returns 404 for invalid UUID format", %{conn: conn} do
      conn =
        conn
        |> auth_conn("read")
        |> get("/api/applications/not-a-uuid")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "PATCH /api/applications/:id/status edge cases" do
    test "returns 404 for non-existent app", %{conn: conn} do
      conn =
        conn
        |> auth_conn("update")
        |> patch("/api/applications/#{Ecto.UUID.generate()}/status", %{
          "status" => "pending_risk"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end
end
