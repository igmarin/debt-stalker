defmodule DebtStalkerWeb.Api.HealthControllerTest do
  @moduledoc """
  Tests for the health check endpoints.
  """
  use DebtStalkerWeb.ConnCase, async: true

  describe "GET /api/health" do
    test "returns healthy status with database connected", %{conn: conn} do
      conn = get(conn, "/api/health")

      assert %{
               "status" => "healthy",
               "database" => "connected",
               "timestamp" => _
             } = json_response(conn, 200)
    end

    test "does not require authentication", %{conn: conn} do
      # No auth header needed
      conn = get(conn, "/api/health")
      assert conn.status == 200
    end
  end

  describe "GET /api/health/live" do
    test "returns 200 alive status without DB check", %{conn: conn} do
      conn = get(conn, "/api/health/live")

      assert %{"status" => "alive", "timestamp" => _} = json_response(conn, 200)
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/api/health/live")
      assert conn.status == 200
    end
  end

  describe "GET /api/health/ready" do
    test "returns ready status with database connected", %{conn: conn} do
      conn = get(conn, "/api/health/ready")

      assert %{
               "status" => "ready",
               "database" => "connected",
               "timestamp" => _
             } = json_response(conn, 200)
    end

    test "does not require authentication", %{conn: conn} do
      conn = get(conn, "/api/health/ready")
      assert conn.status == 200
    end
  end
end
