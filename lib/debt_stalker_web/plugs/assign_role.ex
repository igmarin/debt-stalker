defmodule DebtStalkerWeb.Plugs.AssignRole do
  @moduledoc """
  Reads the browser persona role from the session and assigns `:current_role`.

  The companion UI uses lightweight session roles (`"applicant"` or `"admin"`).
  This plug does not enforce access; enforcement happens in the LiveView
  `on_mount` hook or controller-specific plugs.
  """

  @behaviour Plug

  import Plug.Conn

  @valid_roles ["applicant", "admin"]

  @doc "Initializes plug options."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Assigns `:current_role` from the session if it is valid."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    role = get_session(conn, "role")

    if role in @valid_roles do
      assign(conn, :current_role, role)
    else
      assign(conn, :current_role, nil)
    end
  end
end
