defmodule DebtStalker.SmokeTest do
  @moduledoc false
  use DebtStalker.DataCase, async: true

  alias Ecto.Adapters.SQL

  test "application boots successfully" do
    assert Process.whereis(DebtStalker.Supervisor) != nil
  end

  test "repo connects to database" do
    assert {:ok, %{num_rows: 1}} = SQL.query(DebtStalker.Repo, "SELECT 1")
  end

  test "PubSub is running" do
    assert Process.whereis(DebtStalker.PubSub) != nil
  end
end
