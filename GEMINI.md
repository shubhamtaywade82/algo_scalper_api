# Algo Scalper API — Antigravity Context

## Stack
- Ruby 3.3.4, Rails 8.1.3 (API-only), PostgreSQL, Redis
- DhanHQ for Indian market trading (NSE/BSE/MCX)
- Solid Queue, Solid Cache, Solid Cable
- Ollama for local LLM (technical analysis agent)
- Woods codebase index in `tmp/woods/`

## Project Structure
- `app/services/` — domain services in subdirectories: signal/, options/, orders/, live/, risk/, entries/, capital/, smc/, indicators/, dhan/, adapters/, positions/, trading/
- `app/strategies/` — trading strategy implementations
- `app/controllers/api/` — API endpoints
- `lib/trading_system/` — daemon, bootstrap, supervisor
- `lib/services/ai/` — Ollama client and technical analysis agent

## Key Commands
- `bundle exec rspec` — run tests
- `bundle exec rubocop` — lint
- `bundle exec rake woods:extract` — re-index codebase
- `bundle exec rake woods:incremental` — update index

## MCP
- Woods MCP server is configured globally at `~/.gemini/config/mcp_config.json`
- Provides lookup, search, dependencies, dependents, and graph analysis tools for the codebase
