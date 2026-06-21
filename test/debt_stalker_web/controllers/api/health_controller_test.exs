defmodule DebtStalkerWeb.Api.HealthControllerTest do
  @moduledoc """
  Tests for the health check endpoint.
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
end
