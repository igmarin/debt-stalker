defmodule DebtStalkerWeb.PageController do
  use DebtStalkerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
