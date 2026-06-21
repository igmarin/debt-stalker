defmodule DebtStalker.Vault.EncryptedBinary do
  @moduledoc """
  Cloak Ecto type for encrypted binary fields.
  """
  use Cloak.Ecto.Binary, vault: DebtStalker.Vault
end
