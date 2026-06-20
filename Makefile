.PHONY: setup db migrate seed run test format lint dialyzer docs

setup: ## Install deps, create DB, run migrations
	mix deps.get
	mix ecto.setup
	mix assets.setup
	mix assets.build

db: ## Create + migrate database
	mix ecto.create
	mix ecto.migrate

migrate: ## Run migrations
	mix ecto.migrate

seed: ## Run seeds (empty in Phase 0)
	mix run priv/repo/seeds.exs

run: ## Start Phoenix server
	mix phx.server

test: ## Run full test suite
	mix test

format: ## Format code
	mix format

lint: ## Run credo --strict
	mix credo --strict

dialyzer: ## Run dialyzer
	mix dialyzer

docs: ## Generate ExDoc
	mix docs
