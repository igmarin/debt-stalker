defmodule DebtStalker.Applications.AppCacheTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications

  defp attach_cache_telemetry(event, expected_key) do
    test_pid = self()
    ref = make_ref()

    :telemetry.attach(
      ref,
      event,
      fn _event, measurements, metadata, _config ->
        if metadata.key == expected_key do
          send(test_pid, {event, measurements, metadata})
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  @valid_es_attrs %{
    country: "ES",
    full_name: "Juan Garcia",
    identity_document: "12345678Z",
    requested_amount: Decimal.new("5000"),
    monthly_income: Decimal.new("2000")
  }

  setup do
    Cachex.clear(:app_cache)
    {:ok, app} = Applications.create_application(@valid_es_attrs)
    %{app: app}
  end

  describe "get_application/1 cache behavior" do
    test "second call hits cache (no DB query)", %{app: app} do
      {:ok, app1} = Applications.get_application(app.id)
      assert app1.id == app.id

      cache_key = "app:#{app.id}"
      attach_cache_telemetry([:debt_stalker, :cache, :hit], cache_key)

      {:ok, app2} = Applications.get_application(app.id)
      assert app2.id == app.id

      assert_received {[:debt_stalker, :cache, :hit], _measurements, %{key: ^cache_key}}, 1000
    end

    test "first call is a cache miss", %{app: app} do
      cache_key = "app:#{app.id}"
      attach_cache_telemetry([:debt_stalker, :cache, :miss], cache_key)

      {:ok, app1} = Applications.get_application(app.id)
      assert app1.id == app.id

      assert_received {[:debt_stalker, :cache, :miss], _measurements, %{key: ^cache_key}}, 1000
    end
  end

  describe "update_status/3 cache invalidation" do
    test "status update invalidates cache (next read fetches fresh)", %{app: app} do
      {:ok, app1} = Applications.get_application(app.id)
      assert app1.status == "submitted"

      {:ok, updated} = Applications.update_status(app.id, "pending_risk", "system")
      assert updated.status == "pending_risk"

      {:ok, app2} = Applications.get_application(app.id)
      assert app2.status == "pending_risk"
    end
  end

  describe "PubSub-driven cache invalidation" do
    test "PubSub broadcast triggers cache invalidation", %{app: app} do
      {:ok, _app1} = Applications.get_application(app.id)

      Phoenix.PubSub.subscribe(DebtStalker.PubSub, "applications:#{app.id}")

      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      assert_received {:status_changed,
                       %{from: "submitted", to: "pending_risk", application_id: app_id}},
                      1000

      assert app_id == app.id

      {:ok, app2} = Applications.get_application(app.id)
      assert app2.status == "pending_risk"
    end
  end

  describe "cache hit/miss observability" do
    test "cache hit emits telemetry event", %{app: app} do
      {:ok, _app1} = Applications.get_application(app.id)

      cache_key = "app:#{app.id}"
      attach_cache_telemetry([:debt_stalker, :cache, :hit], cache_key)

      {:ok, _app2} = Applications.get_application(app.id)

      assert_received {[:debt_stalker, :cache, :hit], measurements, %{key: ^cache_key}}, 1000
      assert is_map(measurements)
    end

    test "cache miss emits telemetry event", %{app: app} do
      cache_key = "app:#{app.id}"
      attach_cache_telemetry([:debt_stalker, :cache, :miss], cache_key)

      {:ok, _app1} = Applications.get_application(app.id)

      assert_received {[:debt_stalker, :cache, :miss], measurements, %{key: ^cache_key}}, 1000
      assert is_map(measurements)
    end
  end
end
