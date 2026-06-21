defmodule DebtStalkerWeb.Auth.AuthPlug do
  @moduledoc """
  Plug that verifies JWT tokens from the Authorization header.

  Extracts claims and assigns `:current_role` to the connection.
  Returns 401 if token is missing/invalid.
  """
  import Plug.Conn
  alias DebtStalkerWeb.Auth.Token

  @behaviour Plug

  @doc "Initializes the plug options."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Verifies the JWT token and assigns the current role."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- Token.verify_token(token) do
      assign(conn, :current_role, claims["role"])
    else
      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :missing_token}
    end
  end
end
