# Branch Guide - Complete Reference

## Overview

This document provides a comprehensive guide to all branches in the repository, including branch strategy, relationships, merge priorities, and detailed analysis.

---

## Table of Contents

1. [Branch Strategy](#branch-strategy)
2. [All Branches Overview](#all-branches-overview)
3. [Cursor Branches Analysis](#cursor-branches-analysis)
4. [Base Branch Mapping](#base-branch-mapping)
5. [Merge Mapping and Priorities](#merge-mapping-and-priorities)
6. [Quick Reference](#quick-reference)

---

## Branch Strategy

### Branch Types

#### 1. **Main Branch** (`main`)
- **Purpose**: Production-ready, stable code
- **Protection**: Should be protected, requires PR reviews
- **Integration**: Receives merges from feature branches
- **Status**: ✅ Active

#### 2. **Feature Branches**
- **Naming Patterns**: 
  - `cursor/description` - Cursor AI generated branches
  - `codex/description` - Codex AI generated branches
  - `feature/description` - Standard feature branches
  - `topic-name` - Topic branches
- **Purpose**: Development of new features or enhancements
- **Integration**: Merge to `main` via Pull Request after review

#### 3. **Dependabot Branches**
- **Naming Pattern**: `dependabot/bundler/package-version`
- **Purpose**: Automated dependency updates
- **Integration**: Merge to `main` after review

#### 4. **Release Branches** (Per Git Workflow Rules - Not Currently Active)
- **Naming Pattern**: `patch/VERSION`, `rc/VERSION`
- **Purpose**: Patch releases and release candidates
- **Status**: ⚠️ Not currently active

#### 5. **Hotfix Branches** (Per Git Workflow Rules - Not Currently Active)
- **Naming Pattern**: `hotfix/VERSION`
- **Purpose**: Critical production fixes
- **Status**: ⚠️ Not currently active

### Integration Strategies

#### Current Practice: Direct Feature Branch → Main
```
Feature Branch → Pull Request → Main
```

#### Documented Strategy: Cascading Release (Not Currently Used)
```
patch/VERSION → rc/VERSION → integration → main
```

---

## All Branches Overview

### Statistics
- **Total branches**: ~40+ branches
- **Cursor branches**: 10
- **Dependabot branches**: ~10
- **Topic/Feature branches**: ~20+

### Branch Categories

1. **Cursor Branches** (`cursor/**`) - 10 branches
2. **Dependabot Branches** (`dependabot/**`) - Dependency updates
3. **Topic Branches** - Long-lived feature branches
4. **Main Branch** (`main`) - Production branch

---

## Cursor Branches Analysis

### All 10 Cursor Branches

| Branch | Commits Ahead | Base Branch | Status |
|--------|--------------|-------------|--------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | 6 | `main` | ✅ Ready |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | 128 | `main` | 🔄 Active |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | 116 | `main` | 🔄 Active |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | 94 | `main` | 🔄 Active |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | 69 | `cursor/check-and-optimize-defined-usage-composer-1-58fc` | 🔄 Active |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | 62 | `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | 🔄 Active |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | 62 | `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | 🔄 Active |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | 66 | `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | 🔄 Active |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | 48 | `main` | 🔄 Active |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | 40 | `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | 🔄 Active |

### Cursor Branch Hierarchy

#### Chain 1: Optimization → Modularization → Documentation → Analysis
```
main (30fdba0)
└── cursor/check-and-optimize-defined-usage-composer-1-58fc (94 commits)
    └── cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64 (69 commits)
        └── cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b (62 commits)
            ├── cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574 (62 commits)
            └── cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e (66 commits)
```

#### Chain 2: Risk Management → Risk Exits
```
main (30fdba0)
└── cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65 (48 commits)
    └── cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1 (40 commits)
```

#### Independent Branches
```
main (30fdba0)
├── cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (6 commits) ✅ Ready
├── cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b (128 commits)
└── cursor/explain-signal-scheduler-functionality-composer-1-fde6 (116 commits)
```

### Verified Relationships

The following cursor branch relationships have been verified using `git merge-base`:

- ✅ `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` branches from `cursor/check-and-optimize-defined-usage-composer-1-58fc`
- ✅ `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` branches from `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64`
- ✅ `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` branches from `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b`
- ✅ `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` branches from `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65`

---

## Base Branch Mapping

### Key Finding

**All branches** share `main` (commit `30fdba0` - "Update DhanHQ credential handling and documentation") as their merge base with `main`.

### Branches Created From Other Feature Branches

| Branch | Immediate Base Branch | Merge Base Commit |
|--------|----------------------|-------------------|
| `add-glue-components-for-rm-and-pm` | `add-trading-decision-execution-spine` | `37e929f` |
| `check-options-buying-execution` | `paper-trading` | `004705e` |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `cursor/check-and-optimize-defined-usage-composer-1-58fc` | `9ac3e19` |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | `a692611` |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | `aaa7471` |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | `a57abd6` |

### All Other Branches

All other branches (including most cursor branches) were created directly from `main`.

---

## Merge Mapping and Priorities

### Merge Target

**All branches merge into `main`** (production branch)

### High Priority Branches (Ready/Almost Ready)

| Branch | Commits Ahead | Status | Reason |
|--------|--------------|--------|--------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | 6 | ✅ Ready | Documentation, ready to merge |
| `dependabot/bundler/rails-8.1.1` | 1 | ✅ Ready | Security update |
| `multiple_strategies` | 4 | 🔄 Active | Core feature |
| `add-glue-components-for-rm-and-pm` | 1 | 🔄 Active | Core feature |

### Medium Priority Branches (Large but Active)

| Branch | Commits Ahead | Status |
|--------|--------------|--------|
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | 128 | 🔄 Active |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | 116 | 🔄 Active |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | 94 | 🔄 Active |
| `smc_update` | 61 | 🔄 Active |
| `new_trailing` | 60 | 🔄 Active |

### Lower Priority Branches (Dependent on Parent Branches)

Branches that depend on other branches should be merged after their parent branches:

- `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` (depends on `check-and-optimize`)
- `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` (depends on `modularize`)
- `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` (depends on `explain-dhanhq`)
- `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` (depends on `explain-dhanhq`)
- `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` (depends on `implement-underlying-aware-risk-management`)

### Dependabot Branches

All dependabot branches are low priority and can be merged after review:
- `dependabot/bundler/kamal-2.8.2`
- `dependabot/bundler/puma-7.1.0`
- `dependabot/bundler/rubocop-1.81.7`
- `dependabot/bundler/rubocop-performance-1.26.1`
- `dependabot/bundler/shoulda-matchers-7.0.1`
- And others...

---

## Quick Reference

### Current Branch Status

**Current Branch**: `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`
- **Commits ahead of main**: 6
- **Status**: ✅ Ready to merge
- **Base**: `main` (30fdba0)

### Cursor Branches Summary

- **Total**: 10 branches
- **From main**: 5 branches
- **From other cursor branches**: 5 branches
- **Largest**: 128 commits (`integrate-rule-engine`)
- **Smallest**: 6 commits (`list-branch-charts`) ✅ Ready

### Merge Order Recommendation

1. **First**: `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` (ready)
2. **Then**: Independent large branches (`integrate-rule-engine`, `explain-signal-scheduler`, `check-and-optimize`)
3. **Then**: Parent branches in chains (`modularize`, `explain-dhanhq`, `implement-underlying-aware-risk-management`)
4. **Finally**: Dependent branches (children of above)
5. **Also**: Dependabot branches (low priority, can merge anytime)

### Visual Git Graph (Simplified)

```
main (30fdba0)
│
├── cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (HEAD) ✅
├── cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b
├── cursor/explain-signal-scheduler-functionality-composer-1-fde6
├── cursor/check-and-optimize-defined-usage-composer-1-58fc
│   └── cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64
│       └── cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b
│           ├── cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574
│           └── cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e
├── cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65
│   └── cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1
│
├── [Other topic branches...]
└── [Dependabot branches...]
```

---

## Notes

- All branches merge into `main` (not into each other)
- The hierarchy shown is based on verified commit history analysis
- Some branches may have been rebased or had commits cherry-picked
- The merge base with `main` is the same (30fdba0) for all branches
- Verified relationships are marked with ✅

---

## Verification Commands

To verify branch relationships, use:

```bash
# Find merge base between two branches
git merge-base origin/main origin/branch-name

# Check commits ahead of main
git log --oneline origin/main..origin/branch-name | wc -l

# Visualize branch graph
git log --oneline --graph --all --decorate --simplify-by-decoration | grep "branch-name"
```

---

*Last updated: Based on current repository state*
