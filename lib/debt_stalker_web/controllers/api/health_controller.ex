defmodule DebtStalkerWeb.Api.HealthController do
  @moduledoc """
  Health check endpoint for liveness/readiness probes.

  Returns 200 with system status when the application is running
  and the database is reachable.
  """
  use DebtStalkerWeb, :controller

  alias DebtStalker.Repo

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

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
