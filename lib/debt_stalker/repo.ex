defmodule DebtStalker.Repo do
  @moduledoc """
  Ecto repository for DebtStalker.

  Provides data access on top of PostgreSQL via `Ecto.Adapters.Postgres`.
  """

  use Ecto.Repo,
    otp_app: :debt_stalker,
    adapter: Ecto.Adapters.Postgres
end
