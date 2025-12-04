# Immediate Base Branch - Quick Reference

## Which Branch Was Created From Which Branch (Immediate Parent)

### ✅ All Branches Created From `main`

| Branch | Immediate Base |
|--------|---------------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | `main` |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | `main` |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | `main` |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `main` |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `main` |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `main` |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | `main` |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | `main` |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `main` |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `main` |
| `multiple_strategies` | `main` |
| `add-trading-decision-execution-spine` | `main` |
| `supervisor` | `main` |
| `paper-trading` | `main` |
| `codex/check-algo_scalper_api-against-requirements` | `main` |
| `codex/review-algo-scalper-api-implementation` | `main` |
| `dependabot/github_actions/actions/checkout-6` | `main` |
| All `dependabot/bundler/*` branches | `main` |

### 🔀 Branches NOT Created From `main`

| Branch | Immediate Base Branch |
|--------|----------------------|
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | `add-trading-decision-execution-spine` |
| `develop-intraday-trading-bot-with-dhanhq-api` | `add-trading-decision-execution-spine` |
| `deployment` | `supervisor` |
| `check-options-buying-execution` | `paper-trading` |

---

## Visual Tree

```
main
│
├─── cursor/* (10 branches) ──→ main
├─── multiple_strategies ──→ main
├─── add-trading-decision-execution-spine ──→ main
│    ├─── add-glue-components-for-rm-and-pm ──→ add-trading-decision-execution-spine
│    ├─── codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api ──→ add-trading-decision-execution-spine
│    └─── develop-intraday-trading-bot-with-dhanhq-api ──→ add-trading-decision-execution-spine
│
├─── supervisor ──→ main
│    └─── deployment ──→ supervisor
│
├─── paper-trading ──→ main
│    └─── check-options-buying-execution ──→ paper-trading
│
└─── dependabot/* (11 branches) ──→ main
```

---

## Summary

- **18+ branches** created directly from `main`
- **5 branches** created from other feature branches:
  - 3 from `add-trading-decision-execution-spine`
  - 1 from `supervisor`
  - 1 from `paper-trading`

---

## Quick Check Commands

```bash
# See branch graph
git log --oneline --graph --all --decorate --simplify-by-decoration

# Check specific branch relationship
git log --oneline --graph origin/PARENT_BRANCH origin/CHILD_BRANCH --decorate
```
