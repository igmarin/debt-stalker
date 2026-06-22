# Demo seeds — configurable via environment variables.
#
#     mix run priv/repo/seeds.exs
#     SEED_COUNT=25 SEED_MODE=realistic mix run priv/repo/seeds.exs
#     SEED_SCENARIO=dashboard mix run priv/repo/seeds.exs

alias DebtStalker.Seeds.Demo

Demo.options_from_env()
|> Demo.run()
|> then(fn _result -> Demo.print_credentials() end)
