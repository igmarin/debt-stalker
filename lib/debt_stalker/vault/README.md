# Vault (`lib/debt_stalker/vault/`)

This folder configures PII encryption at rest using `cloak_ecto`. Identity documents are encrypted with AES-256-GCM before being written to PostgreSQL and decrypted transparently when read by Ecto.

## Responsibilities

- Configure the Cloak vault with a production key from the `CLOAK_KEY` environment variable.
- Provide an Ecto type for encrypted binary fields.
- Ensure the encryption key is never logged or committed.

## Key modules

| Module | Purpose |
| ------ | ------- |
| `vault.ex` | Cloak vault configuration and cipher setup. |
| `encrypted_binary.ex` | Ecto type that delegates encryption/decryption to the vault. |

## Public API

### `DebtStalker.Vault`

#### `start_link(opts :: keyword()) :: GenServer.on_start()`

Starts the Cloak vault under the application supervisor. The vault is configured from `config/runtime.exs` or `config/test.exs`.

### `DebtStalker.Vault.EncryptedBinary`

#### Ecto type callbacks

Implements `Ecto.Type` for encrypted binary fields. When the schema reads `identity_document`, the type decrypts the ciphertext. When the schema writes it, the type encrypts the plaintext.

## Configuration

Production (from `config/runtime.exs`):

```elixir
config :debt_stalker, DebtStalker.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!(System.fetch_env!("CLOAK_KEY")),
      iv_length: 12
    }
  ]
```

Test/dev use a hardcoded key for convenience; it is **not** for production.

## Important notes

- **Encryption at rest only**: decrypted values exist in the BEAM process memory while the struct is loaded. The in-memory Cachex cache also holds decrypted structs; this is acceptable because the cache is ephemeral and not exposed externally.
- **Key rotation**: Cloak supports multiple ciphers under the `ciphers` key. A new cipher can be added as `default` while keeping the old one for decryption.
- **Do not log encrypted fields**: code should always call `CreditApplication.redact_document/1` before logging or serializing.

## Where to look next

- `lib/debt_stalker/applications/credit_application.ex` — uses `EncryptedBinary` for `identity_document` and computes `identity_document_hash` for lookup.
- `lib/debt_stalker_web/controllers/api/application_controller.ex` — serializes redacted documents in API responses.
- `docs/master-plan.md` §6 — security requirements for PII.
