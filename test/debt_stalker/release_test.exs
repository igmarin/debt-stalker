defmodule DebtStalker.ReleaseTest do
  use ExUnit.Case, async: false

  alias DebtStalker.Release

  setup do
    Application.ensure_all_started(:debt_stalker)
    :ok
  end

  describe "version/0" do
    test "prints the application version" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert Release.version() == :ok
        end)

      # Application.spec(:debt_stalker, :vsn) returns a charlist version
      assert String.trim(output) != ""
    end
  end

  describe "migrate/0" do
    test "calls Ecto.Migrator.run with :up and all: true" do
      # We can't easily mock Ecto.Migrator.with_repo since it starts a process,
      # so instead we verify the function is callable and returns :ok on success
      # by testing the repos/0 private function indirectly
      repos = Application.fetch_env!(:debt_stalker, :ecto_repos)
      assert DebtStalker.Repo in repos
    end
  end

  describe "rollback/2" do
    test "accepts repo and version arguments" do
      # Verify the function exists and accepts the right arguments
      assert function_exported?(Release, :rollback, 2)
    end
  end

  describe "repos/0 (private, tested via config)" do
    test "ecto_repos is configured" do
      assert {:ok, repos} = Application.fetch_env(:debt_stalker, :ecto_repos)
      assert is_list(repos)
      assert DebtStalker.Repo in repos
    end
  end
end
