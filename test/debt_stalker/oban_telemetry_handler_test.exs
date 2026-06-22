defmodule DebtStalker.ObanTelemetryHandlerTest do
  use DebtStalker.DataCase, async: false

  alias DebtStalker.DeadLetter
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
      attach_metric_listener(:oban_handler_test_stop)

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

    test "captures discarded job after {:error, _} failures exhaust retries" do
      job = exhausted_job(id: 904, application_id: Ecto.UUID.generate())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{job: job, worker: job.worker, result: {:error, :timeout}, state: "discarded"}
      )

      assert %DeadLetterJob{job_id: 904, application_id: app_id} =
               Repo.get_by(DeadLetterJob, job_id: 904)

      assert is_binary(app_id)
      assert DeadLetter.count() >= 1
    end
  end

  describe "[:oban, :job, :exception]" do
    test "emits error metric without capturing retryable failures" do
      attach_metric_listener(:oban_handler_test_exception)

      job =
        exhausted_job(id: 903, application_id: Ecto.UUID.generate(), attempt: 1, max_attempts: 3)

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      assert_receive {:oban_metric,
                      %{worker: "DebtStalker.Workers.RiskEvaluationWorker", result: :error}}

      refute Repo.get_by(DeadLetterJob, job_id: 903)
    end

    test "captures job when retry budget is exhausted" do
      job = exhausted_job(id: 901, application_id: Ecto.UUID.generate())

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      assert %DeadLetterJob{job_id: 901, application_id: app_id} =
               Repo.get_by(DeadLetterJob, job_id: 901)

      assert is_binary(app_id)
      assert DeadLetter.count() >= 1
    end

    test "does not capture job when retries remain" do
      job =
        exhausted_job(id: 902, application_id: Ecto.UUID.generate(), attempt: 1, max_attempts: 3)

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      refute Repo.get_by(DeadLetterJob, job_id: 902)
    end

    test "handles exception event without job in metadata gracefully" do
      attach_metric_listener(:oban_handler_test_no_job)

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{worker: "DebtStalker.Workers.RiskEvaluationWorker"}
      )

      assert_receive {:oban_metric,
                      %{worker: "DebtStalker.Workers.RiskEvaluationWorker", result: :error}}
    end
  end

  describe "[:oban, :job, :stop] with various results" do
    test "classifies {:ok, _} as success" do
      attach_metric_listener(:oban_handler_test_ok_tuple)

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{
          worker: "Elixir.DebtStalker.Workers.RiskEvaluationWorker",
          result: {:ok, %{some: :data}}
        }
      )

      assert_receive {:oban_metric, %{result: :success}}
    end

    test "classifies {:error, _} as error" do
      attach_metric_listener(:oban_handler_test_error_tuple)

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{
          worker: "Elixir.DebtStalker.Workers.RiskEvaluationWorker",
          result: {:error, :timeout}
        }
      )

      assert_receive {:oban_metric, %{result: :error}}
    end

    test "classifies arbitrary term as error" do
      attach_metric_listener(:oban_handler_test_arbitrary)

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{
          worker: "Elixir.DebtStalker.Workers.RiskEvaluationWorker",
          result: {:cancel, :some_reason}
        }
      )

      assert_receive {:oban_metric, %{result: :error}}
    end

    test "captures discarded job with atom state" do
      job = exhausted_job(id: 905, application_id: Ecto.UUID.generate())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{job: job, worker: job.worker, result: {:error, :timeout}, state: :discarded}
      )

      assert %DeadLetterJob{job_id: 905} = Repo.get_by(DeadLetterJob, job_id: 905)
    end

    test "does not capture job when state is not discarded" do
      job = exhausted_job(id: 906, application_id: Ecto.UUID.generate())

      :telemetry.execute(
        [:oban, :job, :stop],
        %{duration: 1},
        %{job: job, worker: job.worker, result: :ok, state: "completed"}
      )

      refute Repo.get_by(DeadLetterJob, job_id: 906)
    end
  end

  describe "attach/0 and detach/0" do
    test "attach returns :ok on first call, {:error, :already_exists} on second" do
      ObanTelemetryHandler.detach()
      assert ObanTelemetryHandler.attach() == :ok
      assert {:error, :already_exists} = ObanTelemetryHandler.attach()
    end

    test "detach is safe when not attached" do
      ObanTelemetryHandler.detach()
      assert ObanTelemetryHandler.detach() == :ok
    end
  end

  defp attach_metric_listener(handler_id) do
    :telemetry.attach(
      handler_id,
      [:debt_stalker, :oban, :job, :stop],
      fn _event, _measurements, metadata, _config ->
        send(self(), {:oban_metric, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp exhausted_job(opts) do
    id = Keyword.fetch!(opts, :id)
    application_id = Keyword.fetch!(opts, :application_id)
    attempt = Keyword.get(opts, :attempt, 3)
    max_attempts = Keyword.get(opts, :max_attempts, 3)

    %Oban.Job{
      id: id,
      args: %{"application_id" => application_id},
      worker: "DebtStalker.Workers.RiskEvaluationWorker",
      queue: "default",
      attempt: attempt,
      max_attempts: max_attempts,
      errors: [
        %{
          "at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "attempt" => attempt,
          "error" => "[runtime_error] simulated failure"
        }
      ]
    }
  end
end
