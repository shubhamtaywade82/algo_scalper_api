# Quick Merge Reference: Which Branch → Which Branch

## 🎯 Simple Answer

**All branches merge into `main`** (production branch)

There are **29 branches** that need to merge into `main`.

---

## 📊 Quick Summary

| Branch | Commits | Priority | Status |
|--------|---------|----------|--------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | 2 | 🔴 High | ✅ Ready |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | 128 | 🔴 High | 🔄 Active |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | 116 | 🟡 Medium | 🔄 Active |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | 94 | 🟡 Medium | ⚠️ Review |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | 69 | 🟡 Medium | 🔄 Active |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | 66 | 🟢 Low | 🔄 Active |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | 62 | 🟡 Medium | 🔄 Active |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | 62 | 🟡 Medium | 🔄 Active |
| `smc_update` | 61 | 🟡 Medium | 🔄 Active |
| `new_trailing` | 60 | 🟡 Medium | 🔄 Active |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | 48 | 🔴 High | ⚠️ Review |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | 40 | 🔴 High | ⚠️ Review |
| `multiple_strategies` | 4 | 🔴 High | 🔄 Active |
| `deployment` | 2 | 🟢 Low | 🔄 Active |
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | 2 | 🔴 High | ✅ Ready |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | 2 | 🟡 Medium | 🔄 Active |
| `add-glue-components-for-rm-and-pm` | 1 | 🔴 High | 🔄 Active |
| `develop-intraday-trading-bot-with-dhanhq-api` | 1 | 🟡 Medium | 🔄 Active |
| `dependabot/*` (11 branches) | 1 each | 🟢 Low | ✅ Ready |

---

## 🔴 High Priority (Merge First)

```
cursor/list-branch-charts-and-integration-strategies-composer-1-f94e → main
cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b → main
cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1 → main
cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65 → main
multiple_strategies → main
add-glue-components-for-rm-and-pm → main
add-trading-decision-execution-spine → main
```

---

## 🟡 Medium Priority

```
cursor/explain-signal-scheduler-functionality-composer-1-fde6 → main
cursor/check-and-optimize-defined-usage-composer-1-58fc → main
cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64 → main
cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b → main
cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574 → main
smc_update → main
new_trailing → main
codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api → main
develop-intraday-trading-bot-with-dhanhq-api → main
dependabot/bundler/rails-8.1.1 → main
dependabot/bundler/sidekiq-8.0.9 → main
dependabot/bundler/solid_queue-1.2.4 → main
```

---

## 🟢 Low Priority

```
cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e → main
deployment → main
[All other dependabot branches] → main
```

---

## 📋 Visual Flow

```
                    ┌──────────────┐
                    │     main     │
                    │  (Target)    │
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
    ┌───┴────┐        ┌────┴────┐        ┌────┴────┐
    │  High  │        │ Medium  │        │  Low    │
    │Priority│        │Priority │        │Priority │
    └───┬────┘        └────┬────┘        └────┬────┘
        │                  │                  │
        │                  │                  │
    [7 branches]      [12 branches]      [10 branches]
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                    ┌──────▼───────┐
                    │     main     │
                    │  (Merged)    │
                    └──────────────┘
```

---

## ✅ Current Branch (Ready Now)

**Branch:** `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`  
**Target:** `main`  
**Commits:** 2  
**Action:** Create Pull Request → `main`

---

## 📝 Notes

- **All branches merge into `main`** - there are no intermediate branches
- Large branches (100+ commits) need careful review before merging
- Dependabot branches can be merged in batches after testing
- Some branches may have conflicts - resolve before merging

---

## 🔍 Check Branch Status

```bash
# See which branches need to merge
git branch -r --no-merged main

# Count commits ahead of main
git log --oneline main..origin/BRANCH_NAME | wc -l

# Check for conflicts
git checkout main
git merge --no-commit --no-ff origin/BRANCH_NAME
```

---

For detailed information, see: `BRANCH_MERGE_MAPPING.md`
