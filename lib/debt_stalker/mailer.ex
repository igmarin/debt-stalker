defmodule DebtStalker.Mailer do
  @moduledoc """
  Swoosh mailer for DebtStalker.

  Delivers outbound email using the configured Swoosh adapter.
  """

  use Swoosh.Mailer, otp_app: :debt_stalker
end
