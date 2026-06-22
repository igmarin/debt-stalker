defmodule DebtStalker.Release do
  @moduledoc """
  Release tasks for production deployments.

  Provides functions for running migrations and other maintenance
  tasks inside a release without requiring Mix.
  """

  @doc """
  Runs pending database migrations.

  Intended to be called via `bin/debt_stalker eval "DebtStalker.Release.migrate()"`.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls back the last migration.
  """
  @spec rollback(atom(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Prints the current application version.
  """
  @spec version() :: :ok
  def version do
    load_app()
    IO.puts(Application.spec(:debt_stalker, :vsn))
  end

  defp load_app do
    Application.load(:debt_stalker)
  end

  defp repos do
    Application.fetch_env!(:debt_stalker, :ecto_repos)
  end
end
