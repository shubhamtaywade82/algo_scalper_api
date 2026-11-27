# REPO-001: Complete Single-Repo Consolidation into `algo-scalper`

## Overview
Finish unifying `options-trading-agent` and `algo_scalper_api` into the single `algo-scalper` repository so all local scripts, agent fixes, and MCP/IDE tool configurations work self-contained inside `/home/nemesis/projects/indian-trading/algo-scalper` without depending on `../options-trading-agent` or the `algo_scalper_api` compatibility symlink.

## Problem
After renaming `algo_scalper_api` to `algo-scalper` and subtree-merging `options-trading-agent` into `agent/`:
1. Four uncommitted fixes in `../options-trading-agent` (`intradayCandles` 429 exponential backoff retry + test, and tightened PostgreSQL lease renewal/statement timeouts) were not yet ported into `agent/`.
2. `bin/stop` and `lib/tasks/shadow.rake` still resolve `../options-trading-agent` instead of `agent/`.
3. Tooling configs (`.mcp.json`, `.cursor/mcp.json`, `opencode.json`, `CLAUDE.md`) still point to `/home/nemesis/projects/indian-trading/algo_scalper_api`.

## Scope

### In Scope
- Port `src/dhan/marketData.ts`, `src/persistence/lease.ts`, `src/persistence/session.ts`, and `tests/dhanAdapters.test.ts` improvements into `agent/` with failing-first TDD verification.
- Update `bin/stop` and `lib/tasks/shadow.rake` to target in-repo `agent/` instead of `../options-trading-agent`.
- Update `.mcp.json`, `.cursor/mcp.json`, `opencode.json`, and `CLAUDE.md` workspace paths/headings from `algo_scalper_api` to `algo-scalper`.

### Out of Scope
- Renaming PostgreSQL database names (`algo_scalper_api_*`), Redis cache namespaces, or cross-service JSON contract identifiers (`source.system = 'algo_scalper_api'`).
- Modifying any files belonging to active feature `BUG-001`.

## Acceptance Criteria
- **ACC-001**: `DhanMarketData#intradayCandles` in `agent/src/dhan/marketData.ts` retries HTTP 429 rate-limit failures up to 3 attempts with exponential backoff, verified by `agent/tests/dhanAdapters.test.ts`, and `agent/src/persistence/lease.ts` + `session.ts` use the tightened renewal (`ttlMs / 4`) and statement timeout (`min(4_000, max(1_000, floor(ttlMs / 5)))`), passing `npm --prefix agent test` and `typecheck`.
- **ACC-002**: `bin/stop`, `lib/tasks/shadow.rake`, `.mcp.json`, `.cursor/mcp.json`, `opencode.json`, and `CLAUDE.md` have zero stale `../options-trading-agent` or `/home/nemesis/projects/indian-trading/algo_scalper_api` path references, while passing syntax checks (`bash -n`, `ruby -c`) and JSON validation.
