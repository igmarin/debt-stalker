defmodule DebtStalkerWeb.Live.RoleAuth do
  @moduledoc """
  LiveView `on_mount` hook that enforces the browser persona role.

  Usage:

      on_mount {DebtStalkerWeb.Live.RoleAuth, :applicant}
      on_mount {DebtStalkerWeb.Live.RoleAuth, :admin}
      on_mount {DebtStalkerWeb.Live.RoleAuth, :any}
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  @doc """
  Enforces role access and assigns `:current_role` to the socket.

  - `:applicant` pages redirect to `/` if the role is not `"applicant"`.
  - `:admin` pages redirect to `/` if the role is not `"admin"`.
  - `:any` requires a role to be set but does not restrict it.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(required_role, _params, session, socket) do
    role = session["role"]

    socket = assign(socket, :current_role, role)

    if allowed?(required_role, role) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: redirect_path(required_role))}
    end
  end

  defp allowed?(:any, role) when role in ["applicant", "admin"], do: true
  defp allowed?(:any, _role), do: false
  defp allowed?(required, role) when is_atom(required), do: Atom.to_string(required) == role
  defp allowed?(_required, _role), do: false

  defp redirect_path(:admin), do: "/admin/login"
  defp redirect_path(_), do: "/"
end
