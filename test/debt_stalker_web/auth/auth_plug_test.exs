defmodule DebtStalkerWeb.Auth.AuthPlugTest do
  use DebtStalkerWeb.ConnCase, async: true

  alias DebtStalkerWeb.Auth.{AuthPlug, Token}

  describe "call/2" do
    test "assigns current_role for valid token", %{conn: conn} do
      {:ok, token} = Token.generate_token("read")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> AuthPlug.call([])

      assert conn.assigns[:current_role] == "read"
      refute conn.halted
    end

    test "returns 401 for missing authorization header", %{conn: conn} do
      conn = AuthPlug.call(conn, [])
      assert conn.status == 401
      assert conn.halted
    end

    test "returns 401 for invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid.token")
        |> AuthPlug.call([])

      assert conn.status == 401
      assert conn.halted
    end
  end
end
