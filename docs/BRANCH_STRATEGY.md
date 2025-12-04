# Branch Strategy and Integration Guide

## Overview

This document outlines the branching strategy, branch types, and integration workflows used in the Algo Scalper API repository.

---

## Branch Types

### 1. **Main Branch** (`main`)
- **Purpose**: Production-ready, stable code
- **Protection**: Should be protected, requires PR reviews
- **Integration**: Receives merges from release branches and hotfixes
- **Status**: ✅ Active

### 2. **Feature Branches**
- **Naming Pattern**: `feature/description` or `cursor/description` or `codex/description`
- **Purpose**: Development of new features or enhancements
- **Examples**:
  - `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`
  - `codex/review-algo-scalper-api-implementation`
  - `develop-intraday-trading-bot-with-dhanhq-api`
- **Integration**: Merge to `main` via Pull Request after review

### 3. **Release Branches** (Per Git Workflow Rules)
- **Naming Pattern**: `patch/VERSION`, `rc/VERSION`
- **Purpose**: 
  - `patch/VERSION`: Patch releases (e.g., `patch/1.0.0`)
  - `rc/VERSION`: Release candidates (e.g., `rc/1.0.0`)
- **Integration**: Cascading merge strategy (see below)
- **Status**: ⚠️ Not currently active in repository

### 4. **Hotfix Branches** (Per Git Workflow Rules)
- **Naming Pattern**: `hotfix/VERSION`
- **Purpose**: Critical production fixes (e.g., `hotfix/1.0.1`)
- **Integration**: Merge directly to `main` and release branches
- **Status**: ⚠️ Not currently active in repository

### 5. **Auto-Merge Branches** (Per Git Workflow Rules)
- **Naming Pattern**: `auto/SOURCE-into-TARGET`
- **Purpose**: Automated cascading merges between branches
- **Example**: `auto/patch-1.0.0-into-rc-1.0.0`
- **Status**: ⚠️ Not currently active in repository

### 6. **QA Test Branches** (Per Git Workflow Rules)
- **Naming Pattern**: `qa-test-management-DATE`
- **Purpose**: QA testing branches
- **Status**: ⚠️ Not currently active in repository

### 7. **Topic Branches** (Current Repository)
- **Examples**:
  - `paper-trading` - Paper trading implementation
  - `multiple_strategies` - Multiple strategy support
  - `supervisor` - Trading supervisor service
  - `deployment` - Deployment configuration
- **Purpose**: Long-lived feature development branches
- **Integration**: Merge to `main` when feature is complete

### 8. **Dependabot Branches**
- **Naming Pattern**: `dependabot/bundler/package-version`
- **Purpose**: Automated dependency updates
- **Examples**:
  - `dependabot/bundler/rails-8.1.1`
  - `dependabot/bundler/kamal-2.8.2`
- **Integration**: Merge to `main` after review

---

## Integration Strategies

### Strategy 1: Direct Feature Branch → Main (Current Practice)

```
Feature Branch → Pull Request → Main
```

**Flow:**
1. Create feature branch from `main`
2. Develop feature
3. Create Pull Request targeting `main`
4. Code review and approval
5. Merge to `main`
6. Deploy from `main`

**Used For:**
- New features
- Bug fixes
- Enhancements
- Dependency updates

---

### Strategy 2: Cascading Release Strategy (Per Git Workflow Rules)

```
patch/VERSION → rc/VERSION → integration → main
```

**Flow:**
1. Create `patch/VERSION` branch from `main`
2. Apply patch fixes
3. Create `auto/patch-VERSION-into-rc-VERSION` branch
4. Merge `patch/VERSION` → `rc/VERSION`
5. Test release candidate
6. Create `auto/rc-VERSION-into-integration` branch
7. Merge `rc/VERSION` → `integration`
8. Integration testing
9. Merge `integration` → `main`
10. Tag release and deploy

**Used For:**
- Production releases
- Versioned releases
- Controlled rollouts

**Cascading Merge Pattern:**
```
patch/1.0.0
  ↓ (auto-merge branch)
rc/1.0.0
  ↓ (auto-merge branch)
integration
  ↓ (final merge)
main
```

---

### Strategy 3: Hotfix Strategy (Per Git Workflow Rules)

```
Hotfix Branch → Main + Release Branches
```

**Flow:**
1. Create `hotfix/VERSION` branch from `main`
2. Apply critical fix
3. Merge to `main` (immediate)
4. Merge to active release branches (`patch/*`, `rc/*`)
5. Deploy immediately

**Used For:**
- Critical production bugs
- Security fixes
- Data integrity issues

**Hotfix Merge Pattern:**
```
hotfix/1.0.1
  ├─→ main (immediate)
  ├─→ patch/1.0.0 (if exists)
  └─→ rc/1.0.0 (if exists)
```

---

## Branch Lifecycle

### Feature Branch Lifecycle

```
1. Create: git checkout -b feature/new-feature main
2. Develop: Make changes, commit frequently
3. Test: Run tests, linting, security scans
4. PR: Create Pull Request targeting main
5. Review: Code review, address feedback
6. Merge: Squash merge or merge commit
7. Cleanup: Delete branch after merge
```

### Release Branch Lifecycle

```
1. Create: git checkout -b patch/1.0.0 main
2. Prepare: Cherry-pick fixes, update version
3. Test: Run full test suite
4. Cascade: Create auto-merge branches
5. Release: Tag version, deploy
6. Maintain: Keep for hotfixes if needed
```

---

## Current Repository Branch Structure

### Active Branches

```
main (production)
├── cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (current)
├── paper-trading (topic branch)
├── multiple_strategies (topic branch)
├── supervisor (topic branch)
├── deployment (deployment config)
└── [various feature branches]
```

### Remote Branches

- **Feature Branches**: `cursor/*`, `codex/*`, `develop-*`
- **Topic Branches**: `paper-trading`, `multiple_strategies`, `supervisor`
- **Dependabot**: `dependabot/bundler/*`
- **Legacy**: Various old feature branches

---

## Branch Naming Conventions

### Required Patterns (Per Git Workflow Rules)

| Branch Type | Pattern | Example |
|------------|---------|---------|
| Patch Release | `patch/VERSION` | `patch/1.0.0` |
| Release Candidate | `rc/VERSION` | `rc/1.0.0` |
| Hotfix | `hotfix/VERSION` | `hotfix/1.0.1` |
| Auto-Merge | `auto/SOURCE-into-TARGET` | `auto/patch-1.0.0-into-rc-1.0.0` |
| QA Test | `qa-test-management-DATE` | `qa-test-management-20240101` |

### Current Patterns (In Use)

| Branch Type | Pattern | Example |
|------------|---------|---------|
| Cursor Feature | `cursor/description-composer-1-xxxx` | `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` |
| Codex Feature | `codex/description` | `codex/review-algo-scalper-api-implementation` |
| Topic Branch | `kebab-case` | `paper-trading`, `multiple_strategies` |
| Dependabot | `dependabot/bundler/package-version` | `dependabot/bundler/rails-8.1.1` |

---

## Integration Workflow Best Practices

### Pre-Merge Checklist

- [ ] All tests pass (`bin/rails test`)
- [ ] Code style compliant (`bin/rubocop`)
- [ ] Security scan clean (`bin/brakeman`)
- [ ] Documentation updated
- [ ] Migration tested (if applicable)
- [ ] PR description complete
- [ ] Reviewers assigned
- [ ] CI/CD pipeline passes

### Merge Strategies

1. **Squash Merge** (Recommended for feature branches)
   - Combines all commits into one
   - Cleaner history
   - Use for: Feature branches, bug fixes

2. **Merge Commit** (For release branches)
   - Preserves branch history
   - Shows merge point clearly
   - Use for: Release branches, cascading merges

3. **Rebase and Merge** (Use with caution)
   - Linear history
   - Rewrites commit history
   - Use for: Small, isolated changes

---

## Branch Protection Rules (Recommended)

### Main Branch
- ✅ Require pull request reviews
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Require linear history (optional)
- ✅ Restrict force pushes
- ✅ Restrict deletions

### Release Branches (`patch/*`, `rc/*`)
- ✅ Require pull request reviews
- ✅ Require status checks to pass
- ✅ Restrict force pushes
- ✅ Allow maintainers to bypass (for hotfixes)

---

## Visual Branch Flow Diagrams

### Current Practice: Feature → Main

```
                    ┌─────────────┐
                    │   Feature   │
                    │   Branch    │
                    └──────┬──────┘
                           │
                           │ PR + Review
                           ↓
                    ┌─────────────┐
                    │    Main     │
                    │  (Production)│
                    └─────────────┘
```

### Cascading Release Strategy (Per Rules)

```
                    ┌─────────────┐
                    │    Main     │
                    └──────┬──────┘
                           │
                           │ Create
                           ↓
                    ┌─────────────┐
                    │ patch/1.0.0 │
                    └──────┬──────┘
                           │
                           │ Auto-Merge
                           ↓
                    ┌─────────────┐
                    │  rc/1.0.0   │
                    └──────┬──────┘
                           │
                           │ Auto-Merge
                           ↓
                    ┌─────────────┐
                    │ integration │
                    └──────┬──────┘
                           │
                           │ Final Merge
                           ↓
                    ┌─────────────┐
                    │    Main     │
                    │  (Released) │
                    └─────────────┘
```

### Hotfix Strategy (Per Rules)

```
                    ┌─────────────┐
                    │    Main     │
                    └──────┬──────┘
                           │
                           │ Create Hotfix
                           ↓
                    ┌─────────────┐
                    │hotfix/1.0.1 │
                    └──┬──────┬───┘
                       │      │
                       │      │ Merge to Active Branches
                       │      │
        ┌──────────────┘      └──────────────┐
        │                                     │
        ↓                                     ↓
┌─────────────┐                      ┌─────────────┐
│    Main     │                      │ patch/1.0.0 │
│  (Updated)  │                      │  (Updated)   │
└─────────────┘                      └─────────────┘
```

---

## Migration Path: Current → Standardized

### Current State
- Feature branches merge directly to `main`
- No formal release branch structure
- Topic branches exist for long-lived features

### Recommended Migration
1. **Phase 1**: Establish `integration` branch
   - Create `integration` branch from `main`
   - Use for pre-production testing

2. **Phase 2**: Implement release branches
   - Create `patch/1.0.0` for next release
   - Establish cascading merge workflow

3. **Phase 3**: Consolidate topic branches
   - Merge completed topic branches to `main`
   - Archive or delete obsolete branches

4. **Phase 4**: Standardize naming
   - Migrate to standard naming conventions
   - Update documentation

---

## Branch Cleanup Recommendations

### Branches to Archive/Delete

**Completed Features:**
- Feature branches merged to `main` > 30 days ago
- Topic branches with completed features

**Obsolete Branches:**
- Branches with no activity > 90 days
- Experimental branches that didn't pan out

**Keep Active:**
- `main` - Production branch
- `paper-trading` - Active development
- `multiple_strategies` - Active development
- Current feature branches

### Cleanup Command

```bash
# List merged branches (safe to delete)
git branch --merged main | grep -v "main"

# Delete merged branches
git branch --merged main | grep -v "main" | xargs git branch -d

# Force delete remote branches (after local cleanup)
git push origin --delete branch-name
```

---

## Summary

### Current Integration Strategy
- **Primary**: Feature branches → `main` via Pull Request
- **Status**: ✅ Active and working
- **Complexity**: Low

### Standardized Strategy (Per Rules)
- **Primary**: Cascading releases (`patch` → `rc` → `integration` → `main`)
- **Status**: ⚠️ Not yet implemented
- **Complexity**: Medium-High
- **Benefit**: Better release control and testing

### Recommendation
- **Short-term**: Continue current practice (feature → main)
- **Long-term**: Implement cascading release strategy for major versions
- **Hotfixes**: Implement hotfix workflow for critical fixes

---

## References

- Git Workflow Rules (`.cursorrules`)
- Repository Guidelines (`AGENTS.md`)
- Git Status: `git branch -a`
- Current Branch: `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e`
