defmodule DebtStalkerWeb.Auth.AuthEdgeCasesTest do
  @moduledoc """
  Edge case tests for JWT authentication including expired tokens,
  malformed headers, and tampered claims.
  """
  use DebtStalkerWeb.ConnCase, async: true

  alias DebtStalkerWeb.Auth.Token

  describe "expired token" do
    test "returns 401 for expired token", %{conn: conn} do
      # Generate a token that expired 1 hour ago using JOSE directly
      secret =
        Application.get_env(:debt_stalker, :jwt_secret, "dev-jwt-secret-not-for-production")

      jwk = JOSE.JWK.from_oct(secret)
      jws = %{"alg" => "HS256"}
      claims = %{"role" => "read", "exp" => DateTime.to_unix(DateTime.utc_now()) - 3600}
      {_, token} = JOSE.JWT.sign(jwk, jws, claims) |> JOSE.JWS.compact()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "malformed authorization header" do
    test "returns 401 for Token scheme (not Bearer)", %{conn: conn} do
      {:ok, token} = Token.generate_token("read")

      conn =
        conn
        |> put_req_header("authorization", "Token #{token}")
        |> get("/api/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 for empty Bearer value", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> get("/api/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 for completely invalid token string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not.a.valid.jwt")
        |> get("/api/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 with no authorization header at all", %{conn: conn} do
      conn = get(conn, "/api/applications")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "tampered claims" do
    test "returns 401 for token signed with wrong secret", %{conn: conn} do
      # Sign with a different secret
      jwk = JOSE.JWK.from_oct("wrong-secret-that-does-not-match")
      jws = %{"alg" => "HS256"}
      claims = %{"role" => "update", "exp" => DateTime.to_unix(DateTime.utc_now()) + 3600}
      {_, token} = JOSE.JWT.sign(jwk, jws, claims) |> JOSE.JWS.compact()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/applications")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end

  describe "role enforcement edge cases" do
    test "update role can access read endpoints", %{conn: conn} do
      {:ok, token} = Token.generate_token("update")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/applications")

      assert json_response(conn, 200)
    end

    test "read role cannot access status update endpoint", %{conn: conn} do
      {:ok, read_token} = Token.generate_token("read")
      {:ok, update_token} = Token.generate_token("update")

      # Create an app first
      create_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{update_token}")
        |> post("/api/applications", %{
          "country" => "ES",
          "full_name" => "Test",
          "identity_document" => "12345678Z",
          "requested_amount" => "5000",
          "monthly_income" => "2000"
        })

      %{"data" => %{"id" => id}} = json_response(create_conn, 201)

      # Try to update status with read token
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{read_token}")
        |> patch("/api/applications/#{id}/status", %{"status" => "pending_risk"})

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end
end
