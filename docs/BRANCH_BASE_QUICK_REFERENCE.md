# Branch Base Quick Reference

## Which Branch Was Created From Which Branch

### ✅ Direct From `main` (Most Common - 12+ branches)

All these branches were created directly from `main` at commit `30fdba0`:

```
main (30fdba0)
├── cursor/list-branch-charts-and-integration-strategies-composer-1-f94e
├── cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b
├── cursor/explain-signal-scheduler-functionality-composer-1-fde6
├── cursor/check-and-optimize-defined-usage-composer-1-58fc
├── cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64
├── cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b
├── cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574
├── cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e
├── cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1
├── cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65
├── multiple_strategies
└── dependabot/github_actions/actions/checkout-6
```

### 🔀 From Feature Branch: `add-trading-decision-execution-spine`

```
add-trading-decision-execution-spine (c4d92d8)
├── add-glue-components-for-rm-and-pm
├── codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api
└── develop-intraday-trading-bot-with-dhanhq-api
```

### 🔀 From Feature Branch: `supervisor`

```
supervisor (4e1dbc7)
└── deployment
```

### 🔀 From Feature Branch: `paper-trading`

```
paper-trading
└── check-options-buying-execution
```

---

## Complete List

| Branch | Base Branch | Notes |
|--------|-------------|-------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | `main` | Current branch |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | `main` | |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | `main` | |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `main` | |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `main` | |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `main` | |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | `main` | |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | `main` | |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `main` | |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `main` | |
| `multiple_strategies` | `main` | |
| `dependabot/github_actions/actions/checkout-6` | `main` | |
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` | ⚠️ Not from main |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | `add-trading-decision-execution-spine` | ⚠️ Not from main |
| `develop-intraday-trading-bot-with-dhanhq-api` | `add-trading-decision-execution-spine` | ⚠️ Not from main |
| `deployment` | `supervisor` | ⚠️ Not from main |
| `check-options-buying-execution` | `paper-trading` | ⚠️ Not from main |
| `add-trading-decision-execution-spine` | `main` (older commit) | |
| `supervisor` | `main` (older commit) | |
| `paper-trading` | `main` (older commit) | |
| All `dependabot/bundler/*` | `main` (various commits) | |

---

## Key Findings

1. **12+ branches** created directly from current `main` (30fdba0)
2. **5 branches** created from other feature branches:
   - 3 from `add-trading-decision-execution-spine`
   - 1 from `supervisor`
   - 1 from `paper-trading`
3. **Dependabot branches** created from various historical main commits
4. **No complex hierarchy** - maximum 2 levels deep

---

## Visual Summary

```
                    main (30fdba0)
                    │
        ┌───────────┼───────────┐
        │           │           │
    [12 cursor/]  [multiple]  [dependabot]
    branches      strategies   checkout-6
        │
        │
    ┌───┴───────────────────────────┐
    │                                │
main (older)                    main (older)
    │                                │
    ├── add-trading-decision         ├── supervisor
    │   └── add-glue-components      │   └── deployment
    │   └── codex/add-remaining      │
    │   └── develop-intraday        ├── paper-trading
    │                               │   └── check-options-buying
```

---

## Important Notes

⚠️ **Branches NOT created from main:**
- `add-glue-components-for-rm-and-pm` → Created from `add-trading-decision-execution-spine`
- `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` → Created from `add-trading-decision-execution-spine`
- `develop-intraday-trading-bot-with-dhanhq-api` → Created from `add-trading-decision-execution-spine`
- `deployment` → Created from `supervisor`
- `check-options-buying-execution` → Created from `paper-trading`

These branches may need to be rebased or merged differently than branches created directly from main.
