# Out-of-Sample Validation Criteria

Verify that out-of-sample forward testing returns remain stable across windows.

## Validation Metrics

1. **Walk-Forward Efficiency (WFE)**:
   - $\text{WFE} = \text{Out-of-Sample Expectancy} / \text{In-Sample Expectancy}$.
   - A WFE of $\ge 0.60$ confirms the strategy retains its edge on unseen data.

2. **Out-of-Sample Profit Factor**:
   - Verify that the combined out-of-sample profit factor exceeds $1.40$.

3. **Drawdown Consistency**:
   - Ensure the out-of-sample maximum drawdown does not exceed the in-sample maximum drawdown by more than a 1.5x scaling factor.
