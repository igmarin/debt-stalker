defmodule DebtStalkerWeb.Api.HealthController do
  @moduledoc """
  Health check endpoints for liveness/readiness probes.

  - `GET /api/health` — Full health check (app + DB). Legacy endpoint.
  - `GET /api/health/live` — Liveness probe: app process is running.
  - `GET /api/health/ready` — Readiness probe: app + DB are ready to serve traffic.
  """

  use DebtStalkerWeb, :controller

  alias DebtStalker.Repo

  @doc "Returns the health status of the application and database."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    db_status = check_database()

    status = if db_status == :ok, do: 200, else: 503

    conn
    |> put_status(status)
    |> json(%{
      status: if(status == 200, do: "healthy", else: "unhealthy"),
      database: if(db_status == :ok, do: "connected", else: "unavailable"),
      timestamp: DateTime.utc_now()
    })
  end

  @doc "Liveness probe — returns 200 if the BEAM process is running."
  @spec liveness(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def liveness(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "alive", timestamp: DateTime.utc_now()})
  end

  @doc "Readiness probe — returns 200 if the app can serve traffic (DB reachable)."
  @spec readiness(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def readiness(conn, _params) do
    db_status = check_database()

    status = if db_status == :ok, do: 200, else: 503

    conn
    |> put_status(status)
    |> json(%{
      status: if(status == 200, do: "ready", else: "not_ready"),
      database: if(db_status == :ok, do: "connected", else: "unavailable"),
      timestamp: DateTime.utc_now()
    })
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
