defmodule DebtStalker.Vault do
  @moduledoc """
  Cloak vault for encrypting PII at rest.

  Uses AES-GCM encryption. The key is sourced from:
  - `config/dev.exs` and `config/test.exs`: a hardcoded dev key (not sensitive)
  - `config/runtime.exs`: `$CLOAK_KEY` environment variable (required in prod)
  """
  use Cloak.Vault, otp_app: :debt_stalker
end
