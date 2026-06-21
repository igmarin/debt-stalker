defmodule DebtStalkerWeb.TelemetryTest do
  use DebtStalkerWeb.ConnCase, async: false

  describe "HTTP request telemetry (built-in)" do
    test "emits [:phoenix, :endpoint, :stop] on HTTP request" do
      # Flush any stale messages from previous tests
      flush_telemetry_messages()

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

      assert_receive {[:phoenix, :endpoint, :stop], _measurements, _metadata}, 1000
    end

    test "emits [:phoenix, :router_dispatch, :stop] on routed request" do
      # Flush any stale messages from previous tests
      flush_telemetry_messages()

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

      # Wait for the specific message with route == "/api/health"
      # to avoid picking up stale messages from other tests
      assert_receive {[:phoenix, :router_dispatch, :stop], _measurements,
                      %{route: "/api/health"} = metadata},
                     1000
    end
  end

  defp flush_telemetry_messages do
    receive do
      {[:phoenix | _], _, _} -> flush_telemetry_messages()
    after
      0 -> :ok
    end
  end
end
