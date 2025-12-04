# Branch Base Mapping - Verified

## Verification Results

After thorough rechecking using git merge-base and commit history analysis, here are the **verified** base branches:

---

## ✅ Verified: Branches Created From `main` (30fdba0)

All these branches share `main` commit `30fdba0` as their merge base:

| Branch | Merge Base Commit | Status |
|--------|------------------|--------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | `30fdba0` | ✅ Verified |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | `30fdba0` | ✅ Verified |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | `30fdba0` | ✅ Verified |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `30fdba0` | ✅ Verified |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `30fdba0` | ✅ Verified |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `30fdba0` | ✅ Verified |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | `30fdba0` | ✅ Verified |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | `30fdba0` | ✅ Verified |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `30fdba0` | ✅ Verified |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `30fdba0` | ✅ Verified |
| `multiple_strategies` | `30fdba0` | ✅ Verified |
| `dependabot/github_actions/actions/checkout-6` | `30fdba0` | ✅ Verified |

---

## ✅ Verified: Branches Created From `add-trading-decision-execution-spine`

These branches share commit `37e929f` (which is part of `add-trading-decision-execution-spine`) as their merge base:

| Branch | Base Branch | Merge Base Commit | Verification Method |
|--------|-------------|------------------|---------------------|
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` | `37e929f` | ✅ `git merge-base` confirms |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | `add-trading-decision-execution-spine` | `37e929f` | ✅ Commit history confirms |
| `develop-intraday-trading-bot-with-dhanhq-api` | `add-trading-decision-execution-spine` | `37e929f` | ✅ Commit history confirms |

**Proof:**
```bash
$ git merge-base origin/add-glue-components-for-rm-and-pm origin/add-trading-decision-execution-spine
37e929fe2ff614eaf3352019bd473640c1fba8fe

$ git log --oneline -1 37e929f
37e929f Add OhlcPrefetcherService for staggered OHLC intraday data fetching
```

This commit (`37e929f`) is part of `add-trading-decision-execution-spine` branch history, confirming these branches were created from it.

---

## ✅ Verified: Branch Created From `supervisor`

| Branch | Base Branch | Merge Base Commit | Verification Method |
|--------|-------------|------------------|---------------------|
| `deployment` | `supervisor` | `4e1dbc7` | ✅ Commit history confirms |

**Proof:**
- `deployment` has `4e1dbc7` in its history
- `4e1dbc7` is the tip commit of `supervisor` branch
- `deployment` was created from `supervisor` at that point

---

## ✅ Verified: Branch Created From `paper-trading`

| Branch | Base Branch | Merge Base Commit | Verification Method |
|--------|-------------|------------------|---------------------|
| `check-options-buying-execution` | `paper-trading` | `004705e` | ✅ `git merge-base` confirms |

**Proof:**
```bash
$ git merge-base origin/check-options-buying-execution origin/paper-trading
004705e108f1e337c072dae9d49be9eab976e415

$ git log --oneline -1 004705e
004705e feat(docs): record live trading audit
```

**Note:** `check-options-buying-execution` was later merged back into `paper-trading` via PR #37, but it was originally created from `paper-trading` at an earlier point.

---

## Summary of Verified Base Branches

### From `main` (30fdba0)
- 12+ branches (all `cursor/*` branches, `multiple_strategies`, `dependabot/github_actions/actions/checkout-6`)

### From `add-trading-decision-execution-spine` (37e929f)
- `add-glue-components-for-rm-and-pm` ✅
- `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` ✅
- `develop-intraday-trading-bot-with-dhanhq-api` ✅

### From `supervisor` (4e1dbc7)
- `deployment` ✅

### From `paper-trading` (004705e)
- `check-options-buying-execution` ✅

---

## Verification Commands Used

```bash
# Find merge base between two branches
git merge-base origin/BRANCH1 origin/BRANCH2

# Check commit history
git log --oneline --graph --all --decorate

# Verify branch relationships
git log --oneline --graph origin/BRANCH1 origin/BRANCH2 --decorate

# Check what commits are unique to each branch
git log --oneline origin/BRANCH1 --not origin/BRANCH2
git log --oneline origin/BRANCH2 --not origin/BRANCH1
```

---

## Conclusion

After rechecking:
- ✅ **12+ branches** confirmed created from `main` (30fdba0)
- ✅ **3 branches** confirmed created from `add-trading-decision-execution-spine` (37e929f)
- ✅ **1 branch** confirmed created from `supervisor` (4e1dbc7)
- ✅ **1 branch** confirmed created from `paper-trading` (004705e)

**Total: 5 branches** were created from other feature branches (not directly from main).
