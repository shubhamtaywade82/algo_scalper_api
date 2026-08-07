# Documentation Audit Report (Mandate v2)

This report provides the final audit and classification of the documentation in `docs/` against the codebase (Source of Truth).

## Classification Summary

| Component | Document | Status | Action |
| :--- | :--- | :--- | :--- |
| High-level | `README.md` | VALID | Polish (Completed Phase 8) |
| Architecture | `docs/architecture/system-overview.md` | VALID | Keep |
| Architecture | `docs/architecture/execution-flow.md` | VALID | Rename to `trade-execution-flow.md` |
| Architecture | `docs/architecture/components.md` | VALID | Rename to `component-map.md` |
| Logic | `docs/trading/signal_engine.md` | VALID | Split into `strategy-engine.md` and `signal-generation.md` |
| Risk | `docs/trading/risk_management.md` | VALID | Rename to `risk-management.md` |
| Risk | `docs/trading/safety_mechanisms.md` | VALID | Consolidate into `risk-management.md` or `exit-management.md` |
| Integration | `docs/integrations/dhanhq-api.md` | VALID | Move to `market-data/dhanhq-integration.md` |
| Integration | `docs/integrations/websocket-integration.md` | VALID | Move to `market-data/websocket-feed.md` |
| Infrastructure | `docs/architecture/websocket-feed.md` | VALID | Move to `market-data/websocket-feed.md` |
| Management | `docs/trading/position-management.md` | NEW | Create (from `ActiveCacheService` analysis) |
| Management | `docs/trading/exit-management.md` | NEW | Create (from `ExitEngine` and `UnifiedExitChecker` analysis) |
| Dev | `docs/development/local-setup.md` | VALID | Keep |
| Dev | `docs/development/testing.md` | VALID | Keep |
| Dev | `docs/development/deployment.md` | VALID | Keep |

---

## Proposed New Structure (Phase 6 Alignment)

```text
docs/
├── architecture/
│   ├── system-overview.md
│   ├── trade-execution-flow.md
│   └── component-map.md
├── trading/
│   ├── strategy-engine.md
│   ├── signal-generation.md
│   ├── risk-management.md
│   ├── position-management.md
│   └── exit-management.md
├── market-data/
│   ├── dhanhq-integration.md
│   └── websocket-feed.md
├── development/
│   ├── local-setup.md
│   ├── testing.md
│   └── deployment.md
└── archive/
    └── needs-review/
```

## Discovered Architecture Summary

- **Entrypoint**: `Signal::Scheduler` triggers intervals for indices.
- **Brain**: `Signal::Engine` performs multi-timeframe TA (Supertrend/ADX) or uses `StrategyRecommender`.
- **Validation**: `Entries::EntryGuard` enforces circuit breakers, exposure limits, and daily PnL caps.
- **Execution**: `Orders::EntryManager` resolves strikes via `Options::ChainAnalyzer` and routes to `Orders::Placer`.
- **Active State**: `Positions::ActiveCacheService` maintains real-time tracking in Redis.
- **Safety**: `Live::RiskManagerService` monitors PnL and triggers `Live::ExitEngine` via `UnifiedExitChecker`.
- **Data Backbone**: `Live::MarketFeedHub` manages high-performance WebSocket ticks from DhanHQ.

## Decision
I am ready to proceed with the final folder/file renames and the creation of the missing `position-management.md` and `exit-management.md` documents.
