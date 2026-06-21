defmodule DebtStalker.ObanTelemetryHandlerTest do
  use DebtStalker.DataCase, async: false

  import Ecto.Query

  alias DebtStalker.DeadLetter
  alias DebtStalker.DeadLetter.DeadLetterJob
  alias DebtStalker.ObanTelemetryHandler
  alias DebtStalker.Repo

  setup do
    ObanTelemetryHandler.attach()
    on_exit(fn -> ObanTelemetryHandler.detach() end)
    :ok
  end

  describe "[:oban, :job, :exception] dead-letter capture" do
    test "captures job when retry budget is exhausted" do
      job = exhausted_job(id: 901, application_id: Ecto.UUID.generate())

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      assert [%DeadLetterJob{job_id: 901, application_id: app_id}] =
               Repo.all(from(d in DeadLetterJob, where: d.job_id == 901))

      assert is_binary(app_id)
      assert DeadLetter.count() >= 1
    end

    test "does not capture job when retries remain" do
      job =
        exhausted_job(
          id: 902,
          application_id: Ecto.UUID.generate(),
          attempt: 1,
          max_attempts: 3
        )

      :telemetry.execute(
        [:oban, :job, :exception],
        %{duration: 1},
        %{job: job, worker: job.worker, attempt: job.attempt}
      )

      refute Repo.get_by(DeadLetterJob, job_id: 902)
    end
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