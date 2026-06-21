defmodule DebtStalkerWeb.Auth.Token do
  @moduledoc """
  JWT token generation and verification using Joken.

  Roles:
  - "read": Can list and get applications
  - "update": Can create applications and update status (includes read)
  """
  use Joken.Config

  @impl true
  def token_config do
    default_claims(default_exp: 3600)
    |> add_claim("role", nil, &valid_role?/1)
  end

  @spec generate_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_token(role) when role in ["read", "update"] do
    claims = %{"role" => role}

    case generate_and_sign(claims, signer()) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

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
