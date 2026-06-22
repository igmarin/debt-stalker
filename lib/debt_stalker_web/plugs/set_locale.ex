defmodule DebtStalkerWeb.Plugs.SetLocale do
  @moduledoc """
  Sets the Gettext locale for browser requests.

  The companion UI defaults to Spanish (`es`) for Spain and Mexico.
  """

  @behaviour Plug

  @default_locale "es"

  @doc "Initializes plug options."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Assigns the default locale for the request process."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    Gettext.put_locale(DebtStalkerWeb.Gettext, @default_locale)
    conn
  end
end
