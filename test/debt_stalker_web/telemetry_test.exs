defmodule DebtStalkerWeb.TelemetryTest do
  use DebtStalkerWeb.ConnCase, async: true

  describe "HTTP request telemetry (built-in)" do
    test "emits [:phoenix, :endpoint, :stop] on HTTP request" do
      handler_id = "test-phoenix-endpoint-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:phoenix, :endpoint, :stop],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      conn = build_conn() |> get("/api/health")

      assert conn.status == 200

      assert_received {[:phoenix, :endpoint, :stop], _measurements, _metadata}
    end

    test "emits [:phoenix, :router_dispatch, :stop] on routed request" do
      handler_id = "test-phoenix-router-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:phoenix, :router_dispatch, :stop],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      conn = build_conn() |> get("/api/health")

      assert conn.status == 200

      assert_received {[:phoenix, :router_dispatch, :stop], _measurements, metadata}
      assert metadata.route == "/api/health"
    end
  end
end
