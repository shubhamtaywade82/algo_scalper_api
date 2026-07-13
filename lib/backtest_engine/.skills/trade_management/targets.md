# Profit Target Methodologies

Optimize profit-taking scenarios using structural levels or dynamic targets.

## Target Strategies

1. **Fixed Risk-to-Reward (R-Multiple)**:
   - Close the entire position at a predetermined target (e.g. `2R` or `3R` gain).

2. **Underlying Support / Resistance Targets**:
   - Exit if the underlying spot index hits a major Daily/Hourly pivot, High-Volume Node (HVN), or structural peak.

3. **Option Chain Wall Targets**:
   - Exit calls as the spot index reaches the Call Wall (highest call OI) or exits puts as it reaches the Put Wall (highest put OI).

4. **Trailing Targets**:
   - Instead of exiting instantly, set a target boundary. Once crossed, activate an ultra-tight trailing stop (e.g. 5% trail) to extract remaining momentum.
