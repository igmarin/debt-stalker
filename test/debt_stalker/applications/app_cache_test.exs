defmodule DebtStalker.Applications.AppCacheTest do
  use DebtStalker.DataCase, async: true

  alias DebtStalker.Applications

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

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:debt_stalker, :cache, :hit],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:cache_hit, metadata})
        end,
        nil
      )

      {:ok, app2} = Applications.get_application(app.id)
      assert app2.id == app.id

      assert_received {:cache_hit, %{key: key}}, 1000
      assert key == "app:#{app.id}"

      :telemetry.detach(ref)
    end

    test "first call is a cache miss", %{app: app} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:debt_stalker, :cache, :miss],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:cache_miss, metadata})
        end,
        nil
      )

      {:ok, app1} = Applications.get_application(app.id)
      assert app1.id == app.id

      assert_received {:cache_miss, %{key: key}}, 1000
      assert key == "app:#{app.id}"

      :telemetry.detach(ref)
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

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:debt_stalker, :cache, :hit],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:cache_hit_telemetry, measurements, metadata})
        end,
        nil
      )

      {:ok, _app2} = Applications.get_application(app.id)

      assert_received {:cache_hit_telemetry, measurements, metadata}, 1000
      assert metadata.key == "app:#{app.id}"
      assert is_map(measurements)

      :telemetry.detach(ref)
    end

    test "cache miss emits telemetry event", %{app: app} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:debt_stalker, :cache, :miss],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:cache_miss_telemetry, measurements, metadata})
        end,
        nil
      )

      {:ok, _app1} = Applications.get_application(app.id)

      assert_received {:cache_miss_telemetry, measurements, metadata}, 1000
      assert metadata.key == "app:#{app.id}"
      assert is_map(measurements)

      :telemetry.detach(ref)
    end
  end
end
