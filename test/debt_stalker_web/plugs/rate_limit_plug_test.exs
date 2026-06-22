defmodule DebtStalkerWeb.Plugs.RateLimitPlugTest do
  use DebtStalkerWeb.ConnCase, async: true

  describe "RateLimit plug on /api/auth/token" do
    test "allows requests up to the limit" do
      limit = Application.get_env(:debt_stalker, :rate_limit)[:auth_token][:limit]

      for _ <- 1..limit do
        conn =
          build_conn()
          |> put_req_header("x-forwarded-for", "1.2.3.4")
          |> post(~p"/api/auth/token", %{role: "read"})

        assert conn.status in [200, 400]
      end
    end

    test "returns 429 with Retry-After when limit exceeded" do
      limit = Application.get_env(:debt_stalker, :rate_limit)[:auth_token][:limit]

      for _ <- 1..limit do
        build_conn()
        |> put_req_header("x-forwarded-for", "5.6.7.8")
        |> post(~p"/api/auth/token", %{role: "read"})
      end

      conn =
        build_conn()
        |> put_req_header("x-forwarded-for", "5.6.7.8")
        |> post(~p"/api/auth/token", %{role: "read"})

      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
      assert %{"error" => "rate_limit_exceeded"} = json_response(conn, 429)
    end

    test "different IPs have independent limits" do
      limit = Application.get_env(:debt_stalker, :rate_limit)[:auth_token][:limit]

      for _ <- 1..limit do
        build_conn()
        |> put_req_header("x-forwarded-for", "10.0.0.1")
        |> post(~p"/api/auth/token", %{role: "read"})
      end

      # A different IP should still be allowed
      conn =
        build_conn()
        |> put_req_header("x-forwarded-for", "10.0.0.2")
        |> post(~p"/api/auth/token", %{role: "read"})

      assert conn.status in [200, 400]
    end
  end

  describe "RateLimit plug on /api/webhooks/provider-confirmations" do
    test "returns 429 with Retry-After when limit exceeded" do
      limit = Application.get_env(:debt_stalker, :rate_limit)[:webhook][:limit]

      for _ <- 1..limit do
        build_conn()
        |> put_req_header("x-forwarded-for", "20.0.0.1")
        |> post(~p"/api/webhooks/provider-confirmations", %{})
      end

      conn =
        build_conn()
        |> put_req_header("x-forwarded-for", "20.0.0.1")
        |> post(~p"/api/webhooks/provider-confirmations", %{})

      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
      assert %{"error" => "rate_limit_exceeded"} = json_response(conn, 429)
    end
  end
end
