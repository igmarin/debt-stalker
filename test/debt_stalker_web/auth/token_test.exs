defmodule DebtStalkerWeb.Auth.TokenTest do
  use ExUnit.Case, async: true

  alias DebtStalkerWeb.Auth.Token

  describe "generate_token/1" do
    test "generates valid token for read role" do
      assert {:ok, token} = Token.generate_token("read")
      assert is_binary(token)
    end

    test "generates valid token for update role" do
      assert {:ok, token} = Token.generate_token("update")
      assert is_binary(token)
    end
  end

  describe "verify_token/1" do
    test "verifies a valid read token" do
      {:ok, token} = Token.generate_token("read")
      assert {:ok, claims} = Token.verify_token(token)
      assert claims["role"] == "read"
    end

    test "verifies a valid update token" do
      {:ok, token} = Token.generate_token("update")
      assert {:ok, claims} = Token.verify_token(token)
      assert claims["role"] == "update"
    end

    test "rejects invalid token" do
      assert {:error, _} = Token.verify_token("invalid.token.here")
    end

    test "rejects expired token" do
      signer = Joken.Signer.create("HS256", "dev-jwt-secret-not-for-production")
      claims = %{"role" => "read", "exp" => 0}
      {:ok, token, _} = Joken.encode_and_sign(claims, signer)
      assert {:error, _} = Token.verify_token(token)
    end
  end
end
