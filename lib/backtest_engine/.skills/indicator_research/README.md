# Indicator Research & Feature Engineering Skill

This skill functions as a specialized quantitative researcher responsible for feature engineering. It discovers, validates, and ranks technical features and option-derived indicators.

## Indicator Knowledge Base (IKB)

The Indicator Research skill compiles and maintains a stateful **Indicator Knowledge Base** (IKB) under `data/knowledge_base/indicators/` to serve as a feature foundation for downstream strategy engines:

```text
data/knowledge_base/indicators/
├── formula_library.json             # Code implementations and reference equations
├── implementation_validation.json  # TV/TA-Lib alignment check statistics
├── parameter_database.json          # Optimal parameters per asset and timeframe
├── regime_performance.json          # Win-rate & expectancy of indicators per regime
├── feature_correlation.json         # Correlation and mutual information matrices
└── feature_importance.json          # SHAP and Permutation importance ranks
```

### Downstream Integrations
* **Strategy Generator** asks: *"Give me the top three low-correlation trend features for NIFTY during a trending, low-IV market."* (Checks `regime_performance.json` and `feature_correlation.json`)
* **Risk Manager** asks: *"Which volatility features complement Supertrend without duplicating its information?"* (Checks `feature_correlation.json`)
* **Trade Management** asks: *"Which features maintain the highest predictive power for exit signals during expiry week?"* (Checks `regime_performance.json` and `feature_importance.json`)
