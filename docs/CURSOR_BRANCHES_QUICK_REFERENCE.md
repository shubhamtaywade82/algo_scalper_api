# Cursor Branches - Quick Reference

## All 10 Cursor Branches

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

---

## Branch Chains

### Chain 1: Optimization → Modularization → Documentation → Analysis
```
main
└── cursor/check-and-optimize-defined-usage-composer-1-58fc (94 commits)
    └── cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64 (69 commits)
        └── cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b (62 commits)
            ├── cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574 (62 commits)
            └── cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e (66 commits)
```

### Chain 2: Risk Management → Risk Exits
```
main
└── cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65 (48 commits)
    └── cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1 (40 commits)
```

### Independent Branches
```
main
├── cursor/list-branch-charts-and-integration-strategies-composer-1-f94e (6 commits) ✅ Ready
├── cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b (128 commits)
└── cursor/explain-signal-scheduler-functionality-composer-1-fde6 (116 commits)
```

---

## Merge Priority

### 🔴 High Priority
- `cursor/list-branch-charts-and-integration-strategies-composer-1-f94e` → `main` (6 commits, ready)

### 🟡 Medium Priority
- `cursor/integrate-rule-engine-for-risk-and-positions-management-composer-1-976b` → `main` (128 commits)
- `cursor/explain-signal-scheduler-functionality-composer-1-fde6` → `main` (116 commits)
- `cursor/check-and-optimize-defined-usage-composer-1-58fc` → `main` (94 commits)

### 🟢 Lower Priority (Dependent Branches)
- Merge parent branches first, then:
  - `cursor/modularize-supertrend-adx-indicator-logic-composer-1-da64` → `main`
  - `cursor/explain-dhanhq-ws-and-ltp-storage-composer-1-de8b` → `main`
  - `cursor/adapt-option-trade-parameters-by-volatility-regime-composer-1-d574` → `main`
  - `cursor/analyze-algo-scalper-api-design-patterns-composer-1-837e` → `main`
  - `cursor/implement-underlying-aware-risk-management-and-peak-drawdown-gating-composer-1-8b65` → `main`
  - `cursor/implement-underlying-aware-risk-exits-and-drawdown-gating-gpt-5.1-codex-high-20d1` → `main`

---

## Key Statistics

- **Total cursor branches**: 10
- **Branches from main**: 5
- **Branches from other cursor branches**: 5
- **Largest branch**: 128 commits
- **Smallest branch**: 6 commits
- **Total commits across all branches**: ~691 commits
