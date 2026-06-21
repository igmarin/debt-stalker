defmodule DebtStalker.ObanTelemetryHandlerTest do
  use DebtStalker.DataCase, async: false

  alias DebtStalker.DeadLetter.DeadLetterJob
  alias DebtStalker.ObanTelemetryHandler
  alias DebtStalker.Repo

  setup do
    ObanTelemetryHandler.attach()
    on_exit(fn -> ObanTelemetryHandler.detach() end)
    :ok
  end

  describe "[:oban, :job, :stop]" do
    test "emits business metrics telemetry" do
      handler_id = :oban_handler_test_stop

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :oban, :job, :stop],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:oban_metric, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{
          worker: "Elixir.DebtStalker.Workers.RiskEvaluationWorker",
          result: :ok
        }
      )

      assert_receive {:oban_metric, %{worker: worker, result: :success}}

      assert worker in [
               "DebtStalker.Workers.RiskEvaluationWorker",
               "Elixir.DebtStalker.Workers.RiskEvaluationWorker"
             ]
    end
  end

  describe "[:oban, :job, :exception]" do
    test "emits error metric without capturing retryable failures" do
      handler_id = :oban_handler_test_exception

      :telemetry.attach(
        handler_id,
        [:debt_stalker, :oban, :job, :stop],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:oban_metric, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      job = %Oban.Job{
        id: 903,
        args: %{"application_id" => Ecto.UUID.generate()},
        worker: "DebtStalker.Workers.RiskEvaluationWorker",
        queue: "default",
        attempt: 1,
        max_attempts: 3,
        errors: [%{"error" => "transient"}]
      }

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      assert_receive {:oban_metric,
                      %{worker: "DebtStalker.Workers.RiskEvaluationWorker", result: :error}}

      refute Repo.get_by(DeadLetterJob, job_id: 903)
    end
  end
end
