# Trailing Optimizer Research Skill

This skill functions as a quantitative exit researcher. Its responsibility is to identify which trailing stop rules maximize strategy expectancy under specific market regimes.

## Trailing Intelligence Layer

The Trailing Optimizer writes stateful profiles under `data/knowledge_base/trailing/`:

```text
data/knowledge_base/trailing/
├── method_performance.json        # Expectancy comparisons of trailing stops
├── regime_matrix.json             # Performance matrix of stops vs market regimes
├── activation_rankings.json       # Optimal activation R-multiples
├── parameters_library.json        # Recommended ATR/swing parameters
└── recommended_profiles.json      # Config mapping for Live trade engines
```

### Downstream Integrations
* **Trade Management Engine** queries `recommended_profiles.json` during initialization to select the optimal trailing algorithm.
* **Strategy Generator** queries `regime_matrix.json` to assign exit rules based on strategy bias.
