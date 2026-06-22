defmodule DebtStalkerWeb.Telemetry do
  @moduledoc """
  Telemetry supervisor for DebtStalker.

  Registers Phoenix, database, and VM metrics reporters.
  """

  use Supervisor
  import Telemetry.Metrics

  @doc "Starts the telemetry supervisor."
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc "Initializes the telemetry supervisor children."
  @impl true
  @spec init(term()) :: {:ok, {Supervisor.sup_flags(), [Supervisor.child_spec()]}}
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://telemetry-metrics.hexdocs.pm
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Returns the list of telemetry metrics to be published."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("debt_stalker.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("debt_stalker.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("debt_stalker.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("debt_stalker.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("debt_stalker.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Custom: Status transition metrics
      counter("debt_stalker.status_transition.stop.count",
        event_name: [:debt_stalker, :status_transition, :stop],
        tags: [:to_status],
        description: "Number of status transitions by target status"
      ),

      # Custom: Provider call metrics
      counter("debt_stalker.provider.fetch.stop.count",
        event_name: [:debt_stalker, :provider, :fetch, :stop],
        tags: [:outcome, :country],
        description: "Number of provider calls by outcome and country"
      ),

      # Business: Applications created
      counter("debt_stalker.applications.created.count",
        event_name: [:debt_stalker, :application, :created],
        tags: [:country, :status],
        description: "Number of applications created by country and status"
      ),

      # Business: Provider latency
      summary("debt_stalker.provider.latency.duration",
        event_name: [:debt_stalker, :provider, :latency],
        tags: [:country, :outcome],
        unit: {:native, :millisecond},
        description: "Provider call latency by country and outcome"
      ),

      # Business: Oban job execution
      counter("debt_stalker.oban.jobs.count",
        event_name: [:debt_stalker, :oban, :job, :stop],
        tags: [:worker, :result],
        description: "Number of Oban jobs executed by worker and result"
      )
    ]
  end

  @doc """
  Returns metrics definitions compatible with TelemetryMetricsPrometheus.

  Prometheus does not support `summary` metric types from Telemetry.Metrics.
  This function converts the summary metrics to `distribution` metrics and
  keeps `counter` and `sum` metrics as-is.

  Used by the Prometheus reporter in the application supervision tree.
  """
  @spec prometheus_metrics() :: [Telemetry.Metrics.t()]
  def prometheus_metrics do
    [
      # Phoenix Metrics (distribution for Prometheus)
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000]]
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000]]
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000]]
      ),

      # Database Metrics (distribution for Prometheus)
      distribution("debt_stalker.repo.query.total_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [0.1, 0.5, 1, 5, 10, 50, 100, 500]],
        description: "The sum of the other measurements"
      ),
      distribution("debt_stalker.repo.query.query_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [0.1, 0.5, 1, 5, 10, 50, 100, 500]],
        description: "The time spent executing the query"
      ),
      distribution("debt_stalker.repo.query.queue_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [0.1, 0.5, 1, 5, 10, 50, 100]],
        description: "The time spent waiting for a database connection"
      ),

      # VM Metrics (last_value for Prometheus)
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      # Custom: Status transition metrics
      counter("debt_stalker.status_transition.stop.count",
        event_name: [:debt_stalker, :status_transition, :stop],
        tags: [:to_status],
        description: "Number of status transitions by target status"
      ),

      # Custom: Provider call metrics
      counter("debt_stalker.provider.fetch.stop.count",
        event_name: [:debt_stalker, :provider, :fetch, :stop],
        tags: [:outcome, :country],
        description: "Number of provider calls by outcome and country"
      ),

      # Business: Applications created
      counter("debt_stalker.applications.created.count",
        event_name: [:debt_stalker, :application, :created],
        tags: [:country, :status],
        description: "Number of applications created by country and status"
      ),

      # Business: Provider latency (distribution for Prometheus)
      distribution("debt_stalker.provider.latency.duration",
        event_name: [:debt_stalker, :provider, :latency],
        tags: [:country, :outcome],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000, 5000]],
        description: "Provider call latency by country and outcome"
      ),

      # Business: Oban job execution
      counter("debt_stalker.oban.jobs.count",
        event_name: [:debt_stalker, :oban, :job, :stop],
        tags: [:worker, :result],
        description: "Number of Oban jobs executed by worker and result"
      ),

      # Cache: hit/miss metrics
      counter("debt_stalker.cache.hit.count",
        event_name: [:debt_stalker, :cache, :hit],
        description: "Number of cache hits on application detail reads"
      ),
      counter("debt_stalker.cache.miss.count",
        event_name: [:debt_stalker, :cache, :miss],
        description: "Number of cache misses on application detail reads"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {DebtStalkerWeb, :count_users, []}
    ]
  end
end
