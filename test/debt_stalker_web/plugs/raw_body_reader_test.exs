defmodule DebtStalkerWeb.Plugs.RawBodyReaderTest do
  use ExUnit.Case, async: true

  alias DebtStalkerWeb.Plugs.RawBodyReader

  describe "read_body/2" do
    test "stores the raw body in conn.assigns" do
      conn =
        Plug.Test.conn(
          "POST",
          "/api/webhooks/provider-confirmations",
          "{\"status\":\"approved\"}"
        )

      assert {:ok, "{\"status\":\"approved\"}", conn} =
               RawBodyReader.read_body(conn, length: 1_000_000)

      assert conn.assigns[:raw_body] == "{\"status\":\"approved\"}"
    end

    test "returns :more when body exceeds read length" do
      body = String.duplicate("x", 10_000)
      conn = Plug.Test.conn("POST", "/api/webhooks/provider-confirmations", body)

      assert {:more, _data, _conn} = RawBodyReader.read_body(conn, length: 100)
    end
  end
end
