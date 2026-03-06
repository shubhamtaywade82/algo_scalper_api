# Documentation Audit Report

This report evaluates the existing documentation in the `docs/` directory against the current codebase implementation (Source of Truth).

## Classification Summary

| File | Status | Action | Notes |
| :--- | :--- | :--- | :--- |
| `COMPLETE_SYSTEM_FLOW.md` | VALID | CONSOLIDATE | Highly accurate. Should be the base for Architecture documentation. |
| `SIGNAL_GENERATION_FLOW.md` | VALID | UPDATE | Accurate flow, but needs updates on specific validator names and config keys. |
| `EXIT_MECHANISM_AND_RULES.md` | VALID | UPDATE | Excellent detail. Needs alignment with latest `RiskManagerService` refactors. |
| `TRADING_SYSTEM_GUIDE.md` | VALID | CONSOLIDATE | Good high-level overview. Merge into Guides. |
| `ALGO_CONFIG_USAGE.md` | VALID | MOVE | Useful for developers. Move to Infrastructure. |
| `DhanHQ_API_Integration.md` | VALID | MOVE | Core integration detail. Move to Infrastructure. |
| `SUPER_TREND_INDICATOR.rb.md` | VALID | MOVE | Technical detail on indicator. Move to Trading. |
| `TESTING_GUIDE.md` | VALID | UPDATE | Essential for dev. Update with latest test suites. |
| `README.md` (root) | OUTDATED | REWRITE | Too sparse. Needs to reflect the reconstructed architecture. |

## Detailed Audit Findings

### 1. System Architecture
The `COMPLETE_SYSTEM_FLOW.md` correctly identifies the `Trading::Supervisor` as the orchestrator. The service list and their dependencies are verified against `config/initializers/trading_supervisor.rb`.

### 2. Trading Lifecycle
The `SIGNAL_GENERATION_FLOW.md` and `EXIT_MECHANISM_AND_RULES.md` provide a 90% accurate representation of the code. Minor discrepancies exist in naming conventions (e.g., `Indicators::Supertrend` vs `Indicator::Supertrend`) and some deeply nested risk rules.

### 3. Missing Documentation
- **Circuit Breaker & Edge Failure**: While mentioned in passing, there is no dedicated doc for the emergency halt mechanisms.
- **WebSocket Data Hub**: Deep technical detail on the hub's resilience and fallback logic is thin.
- **SMC Alignment Logic**: The integration with Smart Money Concepts (SMC) via `SmcController` and `SmcScannerJob` is not fully documented.

## Proposed New Structure

```text
docs/
├── architecture/           # High-level system design
│   ├── system_overview.md  (from COMPLETE_SYSTEM_FLOW)
│   ├── components_map.md   (NEW - Phase 3)
│   └── data_flow.md        (NEW - Phase 3)
├── trading/                # Strategy and execution logic
│   ├── signal_engine.md    (from SIGNAL_GENERATION_FLOW)
│   ├── entries_gate.md     (from EntryGuard implementation)
│   └── order_execution.md  (from Placer/Router implementation)
├── risk/                   # Risk management and survival
│   ├── risk_manager.md     (from EXIT_MECHANISM_AND_RULES)
│   ├── circuit_breaker.md  (NEW)
│   └── dynamic_sizing.rb   (from CapitalAllocator implementation)
├── infrastructure/         # External integrations and DevOps
│   ├── dhan_integration.md (from DhanHQ_API_Integration)
│   ├── websocket_hub.md    (NEW)
│   └── redis_cache.md      (NEW)
├── guides/                 # Developer and operator guides
│   ├── setup_guide.md
│   ├── testing_guide.md    (from TESTING_GUIDE)
│   └── troubleshooting.md
└── archive/                # Deprecated or redundant docs
```

## Next Actions
1. **Archive Redundant Files**: Move all current `docs/*.md` to `docs/archive/` after extracting content.
2. **Implement New Structure**: Create directories and populate with cleaned, verified markdown files.
3. **Generate Diagrams**: Use Mermaid to visualize the discovered flows.
4. **Rewrite Root README**: Point to the new documentation structure.
