# Out-of-Sample Robustness Checks

Assess forward test stability using Monte Carlo and parameter sensitivity scans.

## Robustness Tests

1. **Transaction Cost Sensitivity**:
   - Re-evaluate forward test results with doubled slippage and brokerage charges to check if the strategy edge collapses under high execution friction.

2. **Random Trade Removal**:
   - Remove 10% of the winning trades at random from the forward test log.
   - Verify that the strategy remains profitable, ensuring net returns are not dependent on 1 or 2 lucky trades.
