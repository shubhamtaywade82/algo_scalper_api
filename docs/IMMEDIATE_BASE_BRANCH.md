# Immediate Base Branch Mapping

## What This Shows

This document shows the **immediate parent branch** that each branch was created from, not the merge base with main.

---

## Immediate Base Branch for Each Branch

### Branches Created From `main`

All these branches branch directly from `main`:

| Branch | Immediate Base Branch |
|--------|----------------------|
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
| `dependabot/github_actions/actions/checkout-6` | `main` |
| `add-trading-decision-execution-spine` | `main` |
| `supervisor` | `main` |
| `paper-trading` | `main` |
| `codex/check-algo_scalper_api-against-requirements` | `main` |
| `codex/review-algo-scalper-api-implementation` | `main` |
| All `dependabot/bundler/*` branches | `main` |

### Branches Created From `add-trading-decision-execution-spine`

| Branch | Immediate Base Branch |
|--------|----------------------|
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | `add-trading-decision-execution-spine` |
| `develop-intraday-trading-bot-with-dhanhq-api` | `add-trading-decision-execution-spine` |

**Visual Proof:**
```
* c4d92d8 (origin/add-trading-decision-execution-spine) Add autonomous trading scheduler...
| * 62d61b1 (origin/add-glue-components-for-rm-and-pm) Add live position management...
|/  
| * 6c21a96 (origin/develop-intraday-trading-bot-with-dhanhq-api) Add intraday equity...
|/  
| * 567f1fc (origin/codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api) Refine live...
```

### Branch Created From `supervisor`

| Branch | Immediate Base Branch |
|--------|----------------------|
| `deployment` | `supervisor` |

**Visual Proof:**
```
* 4e1dbc7 (origin/supervisor) Refactor PositionTracker...
| * db44399 (origin/deployment) Refactor Worker Configuration...
```

### Branch Created From `paper-trading`

| Branch | Immediate Base Branch |
|--------|----------------------|
| `check-options-buying-execution` | `paper-trading` |

**Visual Proof:**
```
* 8c9a786 (origin/paper-trading) Merge pull request #37...
* 004705e (origin/check-options-buying-execution) feat(docs): record live trading audit
```

---

## Complete Immediate Base Branch Tree

```
main
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
├── dependabot/github_actions/actions/checkout-6
├── add-trading-decision-execution-spine
│   ├── add-glue-components-for-rm-and-pm
│   ├── codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api
│   └── develop-intraday-trading-bot-with-dhanhq-api
├── supervisor
│   └── deployment
├── paper-trading
│   └── check-options-buying-execution
├── codex/check-algo_scalper_api-against-requirements
├── codex/review-algo-scalper-api-implementation
└── [all dependabot/bundler/* branches]
```

---

## Summary Table

| Immediate Base Branch | Number of Child Branches | Child Branches |
|----------------------|-------------------------|----------------|
| `main` | 18+ | All `cursor/*`, `multiple_strategies`, `dependabot/*`, `add-trading-decision-execution-spine`, `supervisor`, `paper-trading`, `codex/*` |
| `add-trading-decision-execution-spine` | 3 | `add-glue-components-for-rm-and-pm`, `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api`, `develop-intraday-trading-bot-with-dhanhq-api` |
| `supervisor` | 1 | `deployment` |
| `paper-trading` | 1 | `check-options-buying-execution` |

---

## Key Differences: Immediate Base vs Merge Base

### Immediate Base Branch
- The branch that was **checked out** when creating a new branch
- Shows the **direct parent** in the branch hierarchy
- Example: `add-glue-components-for-rm-and-pm` → `add-trading-decision-execution-spine`

### Merge Base with Main
- The **common ancestor commit** between a branch and main
- May be different from immediate base if the parent branch has commits
- Example: `add-glue-components-for-rm-and-pm` merge-base with main is `37e929f` (a commit in `add-trading-decision-execution-spine`)

---

## Verification from Git Graph

The git log graph clearly shows:

1. **From `add-trading-decision-execution-spine`:**
   ```
   * c4d92d8 (origin/add-trading-decision-execution-spine)
   | * 62d61b1 (origin/add-glue-components-for-rm-and-pm)
   | * 6c21a96 (origin/develop-intraday-trading-bot-with-dhanhq-api)
   | * 567f1fc (origin/codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api)
   ```

2. **From `supervisor`:**
   ```
   * 4e1dbc7 (origin/supervisor)
   | * db44399 (origin/deployment)
   ```

3. **From `paper-trading`:**
   ```
   * 8c9a786 (origin/paper-trading)
   * 004705e (origin/check-options-buying-execution)
   ```

4. **From `main`:**
   ```
   * 30fdba0 (origin/main)
   | * [all cursor/* branches]
   | * multiple_strategies
   | * [all other branches]
   ```

---

## Notes

- **Most branches (18+)** were created directly from `main`
- **Only 5 branches** were created from other feature branches:
  - 3 from `add-trading-decision-execution-spine`
  - 1 from `supervisor`
  - 1 from `paper-trading`
- The immediate base branch is what you see in the git graph as the parent branch
- This is different from merge-base, which finds the common ancestor commit
