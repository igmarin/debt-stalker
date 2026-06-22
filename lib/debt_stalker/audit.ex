defmodule DebtStalker.Audit do
  @moduledoc """
  Context for the append-only audit trail.

  Currently provides read access to audit log entries. Writes remain in the
  `DebtStalker.Applications` context because status transitions own the
  transaction that creates both the transition and its audit record.
  """

  import Ecto.Query

  alias DebtStalker.Applications.AuditLog
  alias DebtStalker.Repo

  @doc """
  Returns all audit log entries for the given application, newest first.
  """
  @spec list_audit_logs(Ecto.UUID.t()) :: [AuditLog.t()]
  def list_audit_logs(application_id) do
    AuditLog
    |> where([a], a.application_id == ^application_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end
end
