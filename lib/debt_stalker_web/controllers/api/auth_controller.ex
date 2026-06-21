defmodule DebtStalkerWeb.Api.AuthController do
  @moduledoc """
  Token generation endpoint for development/demo purposes.

  POST /api/auth/token with {"role": "read"|"update"} returns a JWT.
  """
  use DebtStalkerWeb, :controller

  alias DebtStalkerWeb.Auth.Token

  @doc "Generates a JWT for the requested role."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"role" => role}) when role in ["read", "update"] do
    case Token.generate_token(role) do
      {:ok, token} ->
        conn
        |> put_status(200)
        |> json(%{token: token, role: role, expires_in: 3600})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "token_generation_failed", reason: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "invalid_role", message: "role must be 'read' or 'update'"})
  end
end
