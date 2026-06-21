defmodule DebtStalker.TelemetryTest do
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
    {:ok, app} = Applications.create_application(@valid_es_attrs)
    %{app: app}
  end

  describe "status transition telemetry" do
    test "emits [:debt_stalker, :status_transition, :stop] on successful transition", %{app: app} do
      handler_id = "test-status-transition-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :status_transition, :stop],
        fn event, measurements, metadata, config ->
          if metadata.application_id == config.app_id do
            send(config.test_pid, {event, measurements, metadata})
          end
        end,
        %{test_pid: self(), app_id: app.id}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _updated} = Applications.update_status(app.id, "pending_risk", "system")

      assert_received {[:debt_stalker, :status_transition, :stop], measurements, metadata}

      assert metadata.application_id == app.id
      assert metadata.country == "ES"
      assert metadata.from_status == "submitted"
      assert metadata.to_status == "pending_risk"
      assert metadata.triggered_by == "system"
      assert is_map(measurements)
    end
  end

  describe "provider call telemetry" do
    test "emits [:debt_stalker, :provider, :fetch, :stop] on successful provider fetch" do
      ref = make_ref()
      handler_id = "test-provider-success-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :provider, :fetch, :stop],
        fn event, measurements, metadata, config ->
          if metadata.outcome == :success do
            send(config.test_pid, {config.ref, event, measurements, metadata})
          end
        end,
        %{test_pid: self(), ref: ref}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _app} = Applications.create_application(@valid_es_attrs)

      assert_received {^ref, [:debt_stalker, :provider, :fetch, :stop], _measurements, metadata}

      assert metadata.country == "ES"
      assert metadata.outcome == :success
    end

    test "emits [:debt_stalker, :provider, :fetch, :stop] with :error outcome on provider failure" do
      ref = make_ref()
      handler_id = "test-provider-failure-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :provider, :fetch, :stop],
        fn event, measurements, metadata, config ->
          if metadata.outcome == :error do
            send(config.test_pid, {config.ref, event, measurements, metadata})
          end
        end,
        %{test_pid: self(), ref: ref}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # "00000000T" passes DNI checksum (0 mod 23 → 'T') and triggers :unavailable in ESAdapter
      failing_attrs = Map.put(@valid_es_attrs, :identity_document, "00000000T")
      {:ok, app} = Applications.create_application(failing_attrs)

      assert_received {^ref, [:debt_stalker, :provider, :fetch, :stop], _measurements, metadata}

      assert metadata.country == "ES"
      assert metadata.outcome == :error
      assert metadata.error_reason == :unavailable
      assert app.status == "provider_error"
    end
  end

  describe "Ecto query telemetry (built-in)" do
    test "emits [:debt_stalker, :repo, :query] on database query" do
      {:ok, agent} = Agent.start_link(fn -> nil end)
      handler_id = "test-ecto-query-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :repo, :query],
        fn event, measurements, metadata, _config ->
          if Process.alive?(agent) do
            Agent.update(agent, fn _ -> {event, measurements, metadata} end)
          end
        end,
        %{}
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)

        try do
          Agent.stop(agent)
        catch
          :exit, _ -> :ok
        end
      end)

      DebtStalker.Repo.all(DebtStalker.Applications.CreditApplication)

      result = Agent.get(agent, & &1)
      assert result != nil
      {event, measurements, _metadata} = result
      assert event == [:debt_stalker, :repo, :query]
      assert is_map(measurements)
      assert Map.has_key?(measurements, :query_time)
    end
  end

  describe "Oban job telemetry (built-in)" do
    test "emits [:oban, :job, :stop] when a worker performs" do
      {:ok, agent} = Agent.start_link(fn -> nil end)
      handler_id = "test-oban-job-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:oban, :job, :stop],
        fn _event, measurements, metadata, _config ->
          if Process.alive?(agent) do
            Agent.update(agent, fn _ -> {measurements, metadata} end)
          end
        end,
        %{}
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)

        try do
          Agent.stop(agent)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, app} = Applications.create_application(@valid_es_attrs)

      :ok =
        Oban.Testing.perform_job(
          DebtStalker.Workers.RiskEvaluationWorker,
          %{"application_id" => app.id},
          queue: :events
        )

      result = Agent.get(agent, & &1)
      assert result != nil
      {_measurements, metadata} = result
      assert metadata.worker == "DebtStalker.Workers.RiskEvaluationWorker"
    end
  end
end
