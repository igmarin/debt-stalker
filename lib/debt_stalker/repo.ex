defmodule DebtStalker.Repo do
  use Ecto.Repo,
    otp_app: :debt_stalker,
    adapter: Ecto.Adapters.Postgres
end
