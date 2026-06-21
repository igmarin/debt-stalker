defmodule DebtStalkerWeb.Api.AuthControllerTest do
  use DebtStalkerWeb.ConnCase, async: true

  describe "POST /api/auth/token" do
    test "returns JWT for read role", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/token", %{role: "read"})

      assert %{"token" => token, "role" => "read", "expires_in" => 3600} =
               json_response(conn, 200)

      assert is_binary(token) and byte_size(token) > 0
    end

    test "returns JWT for update role", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/token", %{role: "update"})
      assert %{"token" => _token, "role" => "update"} = json_response(conn, 200)
    end

    test "returns 400 for invalid role", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/token", %{role: "admin"})
      assert %{"error" => "invalid_role"} = json_response(conn, 400)
    end

    test "returns 400 when role is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/token", %{})
      assert %{"error" => "invalid_role"} = json_response(conn, 400)
    end
  end
end
