defmodule DebtStalkerWeb.Auth.Token do
  @moduledoc """
  JWT token generation and verification using Joken.

  Roles:
  - "read": Can list and get applications
  - "update": Can create applications and update status (includes read)
  """
  use Joken.Config

  @doc "Configures the JWT token claims and validations."
  @impl true
  @spec token_config() :: Joken.token_config()
  def token_config do
    default_claims(default_exp: 3600)
    |> add_claim("role", nil, &valid_role?/1)
  end

  @doc "Generates a signed JWT for the given role."
  @spec generate_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_token(role) when role in ["read", "update"] do
    claims = %{"role" => role}

    case generate_and_sign(claims, signer()) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Verifies a signed JWT and returns its claims."
  @spec verify_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_token(token) do
    verify_and_validate(token, signer())
  end

  defp signer do
    secret = Application.get_env(:debt_stalker, :jwt_secret, "dev-jwt-secret-not-for-production")
    Joken.Signer.create("HS256", secret)
  end

  defp valid_role?(role), do: role in ["read", "update"]
end
