# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Phoenix 1.8 application skeleton with LiveView
- Dependencies: Oban, Joken, Cloak Ecto, Logger JSON, Credo, Dialyxir, ExDoc, Mox, StreamData
- Docker Compose for Postgres 16
- Makefile with all common commands
- CI pipeline (GitHub Actions): format + warnings-as-errors + credo strict + dialyzer + tests
- rs-guard integration: pre-commit hook + review prompt + `.reviewer.toml`
- CodeRabbit CI configuration
- `.credo.exs` with strict checks
- `.dialyzer_ignore.exs` baseline
- `AGENTS.md` development guidelines
- `CHANGELOG.md` (this file)
- `docs/adr/` directory with ADR template
- `docs/postman/debt-stalker.json` collection skeleton
- `.tool-versions` (Elixir 1.18.3 + Erlang 27.3.3)
