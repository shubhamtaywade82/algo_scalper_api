# Walk Forward Analysis Validation Skill

This skill functions as a quantitative validation engine. It evaluates whether strategy parameters generalize cleanly to unseen out-of-sample data.

## Walk Forward Intelligence

The Walk Forward validation engine updates a rolling validation database under `data/knowledge_base/walk_forward/`:

```text
data/knowledge_base/walk_forward/
├── window_performance.json       # Results of each rolling forward test window
├── parameter_evolution.json      # Drift of optimized parameters across windows
└── overfitting_risk.json         # Out-of-sample WFE calculations
```

### Key Valuations
* **Walk-Forward Efficiency (WFE)**: The ratio of out-of-sample (forward) returns to in-sample (optimized) returns.
  - $\text{WFE} \ge 0.60$ is required for a PASS verdict.
* **Parameter Stability Matrix**: Assesses if optimal parameters remain clustered in stable zones or drift erratically.
