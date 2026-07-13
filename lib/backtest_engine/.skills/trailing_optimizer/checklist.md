# Trailing Optimizer Checklist

Use this checklist to verify exit optimizations are robust and statistically sound.

## 1. Trade Log Setup
- [ ] Load completed historical trade logs.
- [ ] Retrieve corresponding minute-level option premium candles.
- [ ] Retrieve underlying spot index candles.
- [ ] Verify that no lookahead bias is present in the data structures.

## 2. Exits Simulation
- [ ] Simulate Fixed Percentage trailing exits.
- [ ] Simulate ATR and Chandelier trailing exits.
- [ ] Simulate Index Swing-Low trailing exits.
- [ ] Simulate Supertrend and EMA trailing exits.

## 3. Activation & Sizing
- [ ] Sweep activation thresholds (0.5R, 1.0R, 1.5R, 2.0R).
- [ ] Sweep trail distance parameters.
- [ ] Calculate Trend Capture % and Exit Efficiency for each run.
- [ ] Select optimal Hybrid configurations (e.g. initial target + trailing remainder).

## 4. Deliverables
- [ ] Generate comparative statistics report.
- [ ] Generate trailing stop recommendation profiles.
- [ ] Update `data/knowledge_base/trailing/`.
