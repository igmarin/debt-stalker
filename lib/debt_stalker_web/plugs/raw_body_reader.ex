defmodule DebtStalkerWeb.Plugs.RawBodyReader do
  @moduledoc """
  Body reader for `Plug.Parsers` that preserves the raw request body.

  Webhook HMAC verification needs the original raw body, but `Plug.Parsers`
  consumes it. This reader stores the body in `conn.assigns[:raw_body]` before
  passing it on.
  """

  @doc """
  Reads the body and stores it in `conn.assigns[:raw_body]`.
  """
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:more, data, conn} ->
        {:more, data, conn}

      {:error, _reason} = error ->
        error
    end
  end
end
