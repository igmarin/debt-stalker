defmodule DebtStalkerWeb.Auth.RequireRolePlug do
  @moduledoc """
  Plug that ensures the current user has the required role.

  Usage in a controller pipeline:
    plug RequireRolePlug, role: "update"

  The "update" role also has "read" access.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    required_role = Keyword.fetch!(opts, :role)
    current_role = conn.assigns[:current_role]

    if has_role?(current_role, required_role) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "forbidden"}))
      |> halt()
    end
  end

  defp has_role?("update", _any), do: true
  defp has_role?(current, required), do: current == required
end
