# Branch Base Mapping: Which Branch Was Created From Which Branch

## Summary

This document shows the **base branch** (parent branch) for each branch in the repository - meaning which branch each feature branch was created from.

---

## Base Branch Analysis

### Branches Created Directly From `main`

Most branches were created directly from `main` at commit `30fdba0` ("Update DhanHQ credential handling and documentation"):

| Branch | Base Branch | Base Commit | Base Commit Message |
|--------|-------------|-------------|---------------------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `multiple_strategies` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |
| `dependabot/github_actions/actions/checkout-6` | `main` | `30fdba0` | Update DhanHQ credential handling and documentation |

### Branches Created From Other Feature Branches

Some branches were created from other feature branches (not directly from `main`):

| Branch | Base Branch | Base Commit | Base Commit Message |
|--------|-------------|-------------|---------------------|
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` | `37e929f` | Add OhlcPrefetcherService for staggered OHLC intraday data fetching |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | `add-trading-decision-execution-spine` | `37e929f` | Add OhlcPrefetcherService for staggered OHLC intraday data fetching |
| `develop-intraday-trading-bot-with-dhanhq-api` | `add-trading-decision-execution-spine` | `37e929f` | Add OhlcPrefetcherService for staggered OHLC intraday data fetching |
| `check-options-buying-execution` | `paper-trading` | `004705e` | feat(docs): record live trading audit |
| `deployment` | `supervisor` | `4e1dbc7` | Refactor PositionTracker and HealthController |

### Dependabot Branches (Created From Various Points)

Dependabot branches were created from different points in history:

| Branch | Base Branch | Base Commit | Base Commit Message |
|--------|-------------|-------------|---------------------|
| `dependabot/bundler/kamal-2.8.2` | `main` | `734e70b` | Update RuboCop configuration and enhance testing guidelines |
| `dependabot/bundler/puma-7.1.0` | `main` | `7e9057b` | Update code style and enhance configuration consistency |
| `dependabot/bundler/rails-8.1.1` | `main` | `446f128` | Disable specific RuboCop rules for integration tests |
| `dependabot/bundler/rubocop-1.81.7` | `main` | `446f128` | Disable specific RuboCop rules for integration tests |
| `dependabot/bundler/rubocop-performance-1.26.1` | `main` | `734e70b` | Update RuboCop configuration and enhance testing guidelines |
| `dependabot/bundler/shoulda-matchers-7.0.1` | `main` | `699a658` | Remove TradingWorker and related trading services |
| `dependabot/bundler/sidekiq-8.0.9` | `main` | `699a658` | Remove TradingWorker and related trading services |
| `dependabot/bundler/solid_queue-1.2.4` | `main` | `446f128` | Disable specific RuboCop rules for integration tests |
| `dependabot/bundler/thruster-0.1.16` | `main` | `7e9057b` | Update code style and enhance configuration consistency |
| `dependabot/bundler/webmock-3.26.1` | `main` | `446f128` | Disable specific RuboCop rules for integration tests |

### Legacy Branches (Created From Older Commits)

| Branch | Base Branch | Base Commit | Base Commit Message |
|--------|-------------|-------------|---------------------|
| `codex/check-algo_scalper_api-against-requirements` | `main` | `166624d` | Align candle helpers and instrument concerns with TA integration |
| `codex/review-algo-scalper-api-implementation` | `main` | `53c763f` | Document automated options buying requirements |
| `add-trading-decision-execution-spine` | `main` | `c4d92d8` | Add autonomous trading scheduler and risk wiring |

---

## Visual Branch Hierarchy

### Direct From Main (Most Common)

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

### Branch From Feature Branch

```
main
└── add-trading-decision-execution-spine (c4d92d8)
    ├── add-glue-components-for-rm-and-pm
    ├── codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api
    └── develop-intraday-trading-bot-with-dhanhq-api
```

```
main
└── supervisor (4e1dbc7)
    └── deployment
```

```
main
└── paper-trading
    └── check-options-buying-execution
```

---

## Complete Branch Base Mapping

### By Base Branch

#### Base: `main` (30fdba0)
- All `cursor/*` branches (10 branches)
- `multiple_strategies`
- `dependabot/github_actions/actions/checkout-6`
- Most `dependabot/bundler/*` branches

#### Base: `add-trading-decision-execution-spine` (37e929f)
- `add-glue-components-for-rm-and-pm`
- `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api`
- `develop-intraday-trading-bot-with-dhanhq-api`

#### Base: `supervisor` (4e1dbc7)
- `deployment`

#### Base: `paper-trading` (004705e)
- `check-options-buying-execution`

#### Base: `main` (Various Older Commits)
- `codex/check-algo_scalper_api-against-requirements` (166624d)
- `codex/review-algo-scalper-api-implementation` (53c763f)
- `add-trading-decision-execution-spine` (c4d92d8)
- Various `dependabot/bundler/*` branches (different commits)

---

## Branch Creation Timeline

### Recent Branches (From Current Main - 30fdba0)
Created after the latest main commit:
- All `cursor/*` branches
- `multiple_strategies`
- `dependabot/github_actions/actions/checkout-6`

### Intermediate Branches (From Feature Branches)
Created from other feature branches:
- `add-glue-components-for-rm-and-pm` → from `add-trading-decision-execution-spine`
- `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` → from `add-trading-decision-execution-spine`
- `develop-intraday-trading-bot-with-dhanhq-api` → from `add-trading-decision-execution-spine`
- `deployment` → from `supervisor`
- `check-options-buying-execution` → from `paper-trading`

### Older Branches (From Historical Main Commits)
Created from older main commits:
- `codex/check-algo_scalper_api-against-requirements` (166624d)
- `codex/review-algo-scalper-api-implementation` (53c763f)
- `add-trading-decision-execution-spine` (c4d92d8)

---

## Key Insights

1. **Most branches branch from `main`** - 12+ branches created directly from current main
2. **Some branches branch from feature branches** - 5 branches created from other feature branches
3. **Dependabot branches** - Created from various historical points in main
4. **No complex branching hierarchy** - Most branches are 1 level deep from main

---

## Commands to Check Base Branch

```bash
# Find merge base with main
git merge-base origin/main origin/BRANCH_NAME

# See commit message of merge base
git log -1 $(git merge-base origin/main origin/BRANCH_NAME)

# See branch graph
git log --oneline --graph --all --decorate --simplify-by-decoration

# Check if branch is based on another branch
git log --oneline origin/BRANCH_NAME..origin/BASE_BRANCH
```

---

## Summary Table

| Base Branch | Number of Child Branches | Example Child Branches |
|-------------|-------------------------|------------------------|
| `main` (30fdba0) | 12+ | All `cursor/*` branches, `multiple_strategies` |
| `add-trading-decision-execution-spine` | 3 | `add-glue-components-for-rm-and-pm` |
| `supervisor` | 1 | `deployment` |
| `paper-trading` | 1 | `check-options-buying-execution` |
| `main` (various older commits) | 10+ | Dependabot branches, legacy branches |

---

## Notes

- **Base branch** = The branch that was checked out when creating a new branch
- **Merge base** = The common ancestor commit between two branches
- Most feature branches were created from `main` at the same commit (30fdba0)
- Some branches were created from other feature branches, creating a 2-level hierarchy
- Dependabot branches are created automatically from the point where dependencies were last updated
