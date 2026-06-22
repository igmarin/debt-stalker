defmodule DebtStalkerWeb.PageController do
  @moduledoc """
  Controller for static marketing/home pages and the admin login flow.

  Admin authentication is intentionally simple for the companion UI:
  a single password stored in the application environment. This is not
  a replacement for a real identity provider, but it prevents casual
  access to the admin dashboard.
  """

  use DebtStalkerWeb, :controller

  @doc "Renders the home page."
  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Sets the browser persona role to applicant.

  The admin role can only be obtained through the password-protected
  login flow, so this endpoint intentionally rejects `role=admin`.
  """
  @spec set_role(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_role(conn, %{"role" => "applicant"}) do
    conn
    |> put_session("role", "applicant")
    |> redirect(to: ~p"/apply")
  end

  def set_role(conn, _params) do
    redirect(conn, to: ~p"/")
  end

  @doc "Renders the admin login form."
  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def login(conn, _params) do
    render(conn, :login)
  end

  @doc "Authenticates the admin password and sets the admin session role."
  @spec do_login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def do_login(conn, %{"password" => password}) do
    if valid_password?(password, admin_password()) do
      conn
      |> put_session("role", "admin")
      |> put_flash(:info, "Welcome back")
      |> redirect(to: ~p"/admin")
    else
      conn
      |> put_flash(:error, "Invalid password")
      |> render(:login)
    end
  end

  def do_login(conn, _params) do
    conn
    |> put_flash(:error, "Password is required")
    |> render(:login)
  end

  @doc "Clears the session and logs the user out."
  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out")
    |> redirect(to: ~p"/")
  end

  @doc "Redirects the legacy applications list to the admin list."
  @spec redirect_applications(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redirect_applications(conn, _params) do
    redirect(conn, to: ~p"/admin/applications")
  end

  @doc "Redirects the legacy new-application route to the applicant form."
  @spec redirect_new_application(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redirect_new_application(conn, _params) do
    redirect(conn, to: ~p"/apply")
  end

  @doc "Redirects legacy application detail URLs to the admin detail page."
  @spec redirect_application_detail(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def redirect_application_detail(conn, %{"id" => id}) do
    redirect(conn, to: ~p"/admin/applications/#{id}")
  end

  defp admin_password do
    Application.fetch_env!(:debt_stalker, :admin_password)
  end

  defp valid_password?(submitted, expected)
       when is_binary(submitted) and is_binary(expected) do
    byte_size(submitted) == byte_size(expected) and
      Plug.Crypto.secure_compare(submitted, expected)
  end

  defp valid_password?(_, _), do: false
end
