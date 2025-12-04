# Branch Graph and Merge Requests (MRs)

## Current Branch Status

**Current Branch:** `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`  
**Base Branch:** `main`  
**Commits Ahead of Main:** 1  
**Merge Base:** `30fdba0` (Update DhanHQ credential handling and documentation)

---

## Branch Graph: Current Branch → Main

### Visual Graph

```
main (30fdba0)
  │
  │ [1 commit ahead]
  │
  └──► cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (HEAD)
         │
         └──► 365179b feat: Add branch strategy and integration guide
```

### Text Representation

```
* 365179b (HEAD -> cursor/list-branch-charts-and-integration-strategies-composer-1-f94e)
  │
  │ [Direct path to main]
  │
* 30fdba0 (main) Update DhanHQ credential handling and documentation
```

### Path to Main

**Direct Path:** The current branch is **directly based on main** with **1 new commit**.

```
Current Branch: cursor/list-branch-charts-and-integration-strategies-composer-1-f94e
    ↓ (1 commit)
Main Branch: main (30fdba0)
```

**To merge to main:**
1. Create Pull Request: `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` → `main`
2. Single commit will be merged: `365179b feat: Add branch strategy and integration guide`
3. No conflicts expected (branch is directly ahead of main)

---

## Merged Pull Requests (MRs) History

### Recent Merged PRs (Chronological Order)

| PR # | Branch | Merge Commit | Description |
|------|--------|--------------|-------------|
| #51 | `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `7b37c1c` | Refactor: Remove redundant service definitions |
| #45 | `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `d91c7ab` | Risk management and peak drawdown gating |
| #44 | `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `1657008` | Underlying-aware risk exits |
| #43 | `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `9266e48` | Underlying-aware risk exits (duplicate) |
| #41 | `supervisor` | `364db63` | Supervisor service implementation |
| #38 | `paper-trading` | `2965e7d` | Paper trading features |
| #37 | `check-options-buying-execution` | `8c9a786` | Options buying execution verification |
| #36 | `paper-trading` | `b3a32bd` | Paper trading features |
| #16 | `refactor-startup-code-for-services` | `2b6c212` | Refactor startup code |
| #15 | `review-algo_scriper_api-for-options-trading-sufficiency` | `cc04867` | API review for options trading |
| #13 | `review-algo_sclaper_api-for-options-trading` | `d23af84` | API review for options trading |
| #12 | `verify-place-order-request-parameters` | `a45e817` | Verify order request parameters |
| #11 | `add-trading-decision-execution-spine` | `9786ce3` | Trading decision execution |
| #3 | `codex/check-algo_scalper_api-against-requirements` | `e1ae579` | Requirements check |
| #2 | `codex/review-algo-scalper-api-implementation` | `0151393` | API implementation review |
| #1 | `dependabot/github_actions/actions/checkout-5` | `daedb57` | Dependabot: Update checkout action |

---

## Main Branch History (Recent Merges)

### First-Parent View (Merge Commits Only)

```
30fdba0 Update DhanHQ credential handling and documentation
6455757 Add .cursorrules file to establish coding standards
4a76d4f Add comprehensive README1.md for Algo Scalper API
364db63 Merge pull request #41 from shubhamtaywade82/supervisor
2e60a4d Implement Position Indexing and Enhance Position Tracker Callbacks
4732439 Refactor TickCache and introduce PnL Updater Service
1ec80f5 Enhance trading analytics and backtesting functionality
0440f26 Enhance RiskManagerService PnL calculations and fallback logic
222c17c Update trading hours logic to use IST timezone across strategies
6c4f5d5 Refactor Signal Engine to integrate strategy recommendations
```

---

## Branch Relationship Graph

### Full Branch Graph (Simplified)

```
main (30fdba0)
  │
  ├──► cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (HEAD)
  │     └──► 365179b feat: Add branch strategy and integration guide
  │
  ├──► cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b
  │     └──► 38e7af1 feat: Add trailing activation percentage feature
  │
  ├──► cursor/explain-signal-scheduler-functionality-composer-1-fde6
  │     └──► 4ae281b feat: Add test planning documentation
  │
  ├──► cursor/check-and-optimize-defined-usage-composer-1-58fc (MERGED #51)
  │     └──► 00eafcb Refactor: Remove redundant service definitions
  │
  ├──► cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64
  │     └──► 22c45df feat: Implement profit protection mechanism
  │
  ├──► cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b
  │     └──► b42eba7 Refactor: Document planned modular indicators system
  │
  ├──► cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574
  │     └──► 8284296 feat: Add comprehensive tests for volatility regime parameters
  │
  ├──► cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e
  │     └──► dea2471 feat: Add PR review documentation
  │
  ├──► smc_update
  │     └──► a2e821b feat: Implement SMC Trading System
  │
  ├──► new_trailing
  │     └──► aaa7471 feat: Enhance EntryGuard and TrailingEngine
  │
  ├──► cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65 (MERGED #45)
  │     └──► d823da2 Refactor: Improve documentation
  │
  ├──► cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1 (MERGED #44, #43)
  │     └──► a57abd6 refactor: Simplify Subscription Logic
  │
  ├──► multiple_strategies
  │     └──► 8c77576 Enhance subscription management
  │
  ├──► supervisor (MERGED #41)
  │     └──► 4e1dbc7 Refactor PositionTracker
  │
  ├──► paper-trading (MERGED #38, #36)
  │     └──► 8c9a786 Merge pull request #37
  │
  └──► [various dependabot branches]
```

---

## Current Branch Details

### Commit Information

**Commit:** `365179b`  
**Message:** `feat: Add branch strategy and integration guide`  
**Author:** Current user  
**Date:** Recent  
**Files Changed:** 
- `docs/BRANCH_STRATEGY.md` (new file)

### Comparison with Main

```bash
# Commits in current branch not in main
git log main..HEAD
# Result: 1 commit (365179b)

# Commits in main not in current branch  
git log HEAD..main
# Result: 0 commits (branch is up to date with main)

# Merge base
git merge-base HEAD main
# Result: 30fdba0 (same as main HEAD)
```

### Merge Readiness

✅ **Ready to Merge:**
- Branch is directly based on main
- No conflicts expected
- Single commit to merge
- Clean history

**Merge Command:**
```bash
# Option 1: Create Pull Request (Recommended)
# Via GitHub/GitLab UI: cursor/list-branch-charts-and-integration-strategies-composer-1-f94e → main

# Option 2: Direct merge (if allowed)
git checkout main
git merge cursor/list-branch-charts-and-integration-strategies-composer-1-f94e
```

---

## Related Branches

### Active Feature Branches (Not Merged)

1. **cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b**
   - Latest: `38e7af1` feat: Add trailing activation percentage feature
   - Status: Active development

2. **cursor/explain-signal-scheduler-functionality-composer-1-fde6**
   - Latest: `4ae281b` feat: Add test planning documentation
   - Status: Active development

3. **cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64**
   - Latest: `22c45df` feat: Implement profit protection mechanism
   - Status: Active development

4. **multiple_strategies**
   - Latest: `8c77576` Enhance subscription management
   - Status: Active development

### Merged Branches (In Main)

- ✅ `cursor/check-and-optimize-defined-usage-composer-1-58fc` (PR #51)
- ✅ `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` (PR #45)
- ✅ `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` (PR #44, #43)
- ✅ `supervisor` (PR #41)
- ✅ `paper-trading` (PR #38, #36)
- ✅ `check-options-buying-execution` (PR #37)

---

## Summary

### Current Branch Status
- **Branch:** `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`
- **Base:** `main` (30fdba0)
- **Commits:** 1 ahead
- **Status:** ✅ Ready to merge

### Path to Main
```
Current Branch (365179b)
    ↓ [1 commit]
Main (30fdba0)
```

### Next Steps
1. Create Pull Request targeting `main`
2. Request review
3. Merge after approval
4. Delete branch after merge

---

## Git Commands Reference

```bash
# View branch graph
git log --oneline --graph --all --decorate -20

# Compare with main
git log --oneline main..HEAD
git log --oneline HEAD..main

# Find merge base
git merge-base HEAD main

# View merge commits
git log --oneline --merges --all -20

# View first-parent (merge commits only)
git log --oneline --first-parent main -10

# Show branch relationships
git show-branch --all --more=10
```
