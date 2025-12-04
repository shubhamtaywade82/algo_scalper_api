# Branch Merge Mapping: Which Branch Needs to Merge Into Which Branch

## Summary

- **Total Branches Not Merged to Main:** 28 branches
- **Branches Already Merged to Main:** 12 branches
- **Target Branch:** `main` (production)

---

## Branches That Need to Merge Into Main

### 1. Feature Branches (Active Development)

| Branch | Commits Ahead | Status | Priority | Merge Target |
|--------|--------------|--------|----------|--------------|
| `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` | 2 | ✅ Ready | High | `main` |
| `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` | 128 | 🔄 Active | High | `main` |
| `cursor/explain-signal-scheduler-functionality-composer-1-fde6` | 116 | 🔄 Active | Medium | `main` |
| `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` | 69 | 🔄 Active | Medium | `main` |
| `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` | 62 | 🔄 Active | Medium | `main` |
| `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` | 62 | 🔄 Active | Medium | `main` |
| `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` | 66 | 🔄 Active | Low | `main` |
| `cursor/check-and-optimize-defined-usage-composer-1-58fc` | 94 | ⚠️ Review | Medium | `main` |
| `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` | 40 | ⚠️ Review | High | `main` |
| `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` | 48 | ⚠️ Review | High | `main` |

### 2. Topic Branches (Long-lived Features)

| Branch | Commits Ahead | Status | Priority | Merge Target |
|--------|--------------|--------|----------|--------------|
| `multiple_strategies` | 4 | 🔄 Active | High | `main` |
| `add-glue-components-for-rm-and-pm` | 1 | 🔄 Active | High | `main` |
| `add-trading-decision-execution-spine` | Multiple | 🔄 Active | High | `main` |
| `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` | 2 | 🔄 Active | Medium | `main` |
| `develop-intraday-trading-bot-with-dhanhq-api` | 1 | 🔄 Active | Medium | `main` |
| `smc_update` | 61 | 🔄 Active | Medium | `main` |
| `new_trailing` | 60 | 🔄 Active | Medium | `main` |
| `deployment` | 2 | 🔄 Active | Low | `main` |

### 3. Dependabot Branches (Dependency Updates)

| Branch | Commits Ahead | Status | Priority | Merge Target |
|--------|--------------|--------|----------|--------------|
| `dependabot/bundler/kamal-2.8.2` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/puma-7.1.0` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/rails-8.1.1` | 1 | ✅ Ready | Medium | `main` |
| `dependabot/bundler/rubocop-1.81.7` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/rubocop-performance-1.26.1` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/shoulda-matchers-7.0.1` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/sidekiq-8.0.9` | 1 | ✅ Ready | Medium | `main` |
| `dependabot/bundler/solid_queue-1.2.4` | 1 | ✅ Ready | Medium | `main` |
| `dependabot/bundler/thruster-0.1.16` | 1 | ✅ Ready | Low | `main` |
| `dependabot/bundler/webmock-3.26.1` | 1 | ✅ Ready | Low | `main` |
| `dependabot/github_actions/actions/checkout-6` | 1 | ✅ Ready | Low | `main` |

### 4. Legacy/Review Branches

| Branch | Commits Ahead | Status | Priority | Merge Target |
|--------|--------------|--------|----------|--------------|
| `codex/check-algo_scalper_api-against-requirements` | 0 | ✅ Merged | N/A | Already merged |
| `codex/review-algo-scalper-api-implementation` | 0 | ✅ Merged | N/A | Already merged |
| `check-options-buying-execution` | 0 | ✅ Merged | N/A | Already merged (PR #37) |

---

## Merge Priority Matrix

### 🔴 High Priority (Merge Soon)

**Feature Branches:**
1. `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` → `main`
   - **Reason:** Documentation, ready to merge
   - **Commits:** 1
   - **Status:** ✅ Ready

2. `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` → `main`
   - **Reason:** Risk management features
   - **Commits:** 128 commits
   - **Status:** 🔄 Active development (large branch, needs careful review)

3. `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` → `main`
   - **Reason:** Critical risk management fixes
   - **Commits:** 40 commits
   - **Status:** ⚠️ Needs review

4. `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` → `main`
   - **Reason:** Risk management enhancements
   - **Commits:** 48 commits
   - **Status:** ⚠️ Needs review

**Topic Branches:**
5. `multiple_strategies` → `main`
   - **Reason:** Core feature
   - **Commits:** 4 commits
   - **Status:** 🔄 Active

6. `add-glue-components-for-rm-and-pm` → `main`
   - **Reason:** Position management features
   - **Commits:** 1 commit
   - **Status:** 🔄 Active

7. `add-trading-decision-execution-spine` → `main`
   - **Reason:** Trading execution features
   - **Commits:** Multiple
   - **Status:** 🔄 Active

### 🟡 Medium Priority

**Feature Branches:**
- `cursor/explain-signal-scheduler-functionality-composer-1-fde6` → `main`
- `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` → `main`
- `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` → `main`
- `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` → `main`
- `cursor/check-and-optimize-defined-usage-composer-1-58fc` → `main`

**Dependency Updates:**
- `dependabot/bundler/rails-8.1.1` → `main` (Rails upgrade)
- `dependabot/bundler/sidekiq-8.0.9` → `main` (Sidekiq upgrade)
- `dependabot/bundler/solid_queue-1.2.4` → `main` (Solid Queue upgrade)

### 🟢 Low Priority

**Documentation/Review:**
- `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` → `main`
- `codex/add-remaining-tasks-to-todo.md-for-algo_scalper_api` → `main`

**Dependency Updates (Non-critical):**
- All other `dependabot/bundler/*` branches → `main`

---

## Visual Merge Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        MAIN BRANCH                          │
│                    (Production Target)                      │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        │                   │                   │
    ┌───┴────┐         ┌────┴────┐        ┌────┴────┐
    │ High  │         │ Medium  │        │  Low    │
    │Priority│        │Priority │        │Priority │
    └───┬────┘         └────┬────┘        └────┬────┘
        │                   │                   │
        │                   │                   │
    ┌───┴───────────────────┴───────────────────┴───┐
    │                                                 │
    │  Feature Branches                               │
    │  Topic Branches                                 │
    │  Dependabot Branches                            │
    │                                                 │
    └─────────────────────────────────────────────────┘
```

## Detailed Merge Instructions

### Current Branch (Immediate Action)

**Branch:** `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`  
**Target:** `main`  
**Action:** Create Pull Request

```bash
# Create PR via GitHub/GitLab UI
Source: cursor/list-branch-charts-and-integration-strategies-composer-1-f94e
Target: main
Title: "feat: Add branch strategy and integration guide"
```

### High Priority Merges

#### 1. Rule Engine Integration
```
cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b
    ↓
main
```
**Commits:** 128 commits (⚠️ Large branch)  
**Files:** Risk management, rule engine  
**Status:** Active development, needs extensive testing and review

#### 2. Risk Management Fixes
```
cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1
    ↓
main
```
**Commits:** 40 commits  
**Files:** EntryGuard, RiskManagerService  
**Status:** Needs code review

#### 3. Multiple Strategies
```
multiple_strategies
    ↓
main
```
**Commits:** Multiple  
**Files:** Strategy management  
**Status:** Active development

### Dependency Updates (Batch Merge)

All `dependabot/bundler/*` branches can be merged together:

```
dependabot/bundler/rails-8.1.1
dependabot/bundler/sidekiq-8.0.9
dependabot/bundler/solid_queue-1.2.4
dependabot/bundler/kamal-2.8.2
dependabot/bundler/puma-7.1.0
dependabot/bundler/rubocop-1.81.7
dependabot/bundler/rubocop-performance-1.26.1
dependabot/bundler/shoulda-matchers-7.0.1
dependabot/bundler/thruster-0.1.16
dependabot/bundler/webmock-3.26.1
    ↓
main (merge all together after testing)
```

---

## Merge Checklist

### Before Creating PR

- [ ] Branch is up to date with `main`
- [ ] All tests pass (`bin/rails test`)
- [ ] Code style compliant (`bin/rubocop`)
- [ ] Security scan clean (`bin/brakeman`)
- [ ] Documentation updated
- [ ] No merge conflicts

### PR Requirements

- [ ] Clear description of changes
- [ ] Link to related issues/tickets
- [ ] Verification steps included
- [ ] Request reviewers
- [ ] Add appropriate labels

### After Merge

- [ ] Delete merged branch
- [ ] Update documentation if needed
- [ ] Deploy to staging/production
- [ ] Monitor for issues

---

## Branch Status Legend

- ✅ **Ready** - Ready to merge, all checks pass
- 🔄 **Active** - Currently in active development
- ⚠️ **Review** - Needs code review before merge
- 🚫 **Blocked** - Cannot merge (conflicts, failing tests)
- ✅ **Merged** - Already merged to main

---

## Summary Table

| Category | Count | Target Branch |
|----------|-------|---------------|
| Feature Branches | 10 | `main` |
| Topic Branches | 8 | `main` |
| Dependabot Branches | 11 | `main` |
| Legacy/Review Branches | 2 | Already merged |
| **Total Pending** | **29** | **`main`** |

---

## Next Steps

1. **Immediate:** Merge `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` → `main`
2. **This Week:** Review and merge high-priority risk management branches
3. **This Month:** Merge active feature branches after testing
4. **Ongoing:** Merge dependabot branches in batches after testing

---

## Notes

- All branches merge into `main` (no intermediate branches like `develop` or `staging`)
- Some branches may have been merged but not deleted (check PR history)
- Dependabot branches are safe to merge but should be tested together
- Feature branches should be reviewed individually before merging
