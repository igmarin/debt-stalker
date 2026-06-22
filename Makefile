.PHONY: setup db migrate seed run test coverage format lint dialyzer docs check ci up down

setup: ## Install deps, create DB, run migrations, seed
	mix deps.get
	mix ecto.setup
	mix assets.setup
	mix assets.build

db: ## Create + migrate database
	mix ecto.create
	mix ecto.migrate

migrate: ## Run migrations
	mix ecto.migrate

seed: ## Run seeds (1_000 demo apps by default; override with SEED_COUNT/SEED_MODE)
	mix run priv/repo/seeds.exs

run: ## Start Phoenix server (ensure Postgres is up)
	mix phx.server

test: ## Run full test suite
	MIX_ENV=test mix ecto.create --quiet
	MIX_ENV=test mix ecto.migrate --quiet
	mix test

coverage: ## Run tests with coverage report (85% threshold)
	MIX_ENV=test mix ecto.create --quiet
	MIX_ENV=test mix ecto.migrate --quiet
	mix test --cover

format: ## Format code
	mix format

lint: ## Run credo --strict
	mix credo --strict

dialyzer: ## Run dialyzer
	mix dialyzer

docs: ## Generate ExDoc
	mix docs

check: ## Run format check + credo + dialyzer
	mix format --check-formatted
	mix credo --strict
	mix dialyzer

ci: check test ## Full CI pipeline locally

up: ## Start Postgres via Docker Compose
	docker compose up -d
	@echo "Waiting for Postgres..."
	@until docker compose exec postgres pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	@echo "Postgres ready"

down: ## Stop Docker Compose services
	docker compose down
