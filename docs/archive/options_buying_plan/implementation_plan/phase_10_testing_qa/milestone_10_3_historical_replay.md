# Milestone 10.3: Historical Replay & Walk-Forward Testing

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Validate strategies on historical data before deployment.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement HistoricalReplayEngine
- [x] Implemented via backtest runners and signal verification tasks replaying historical OHLCV data through the indicator engines

### 2. Create ReplaySpeedController
- [x] Ticks/candles processed sequentially at maximum possible rate to complete backtest simulations rapidly

### 3. Add ReplayMetricsCollector
- [x] Collects realized PnL, win rates, Sharpe ratios, and expectancy statistics per backtest run

### 4. Implement WalkForwardTestRunner
- [x] Handled inside the optimization suites running indicators retuning across training windows and validation sets

### 5. Create MonteCarloSimulator
- [x] Downside drawdown simulation models evaluate probability of ruin and streak risks based on historic stats

### 6. Add ParameterOptimization
- [x] Implemented via `Optimization::IndicatorOptimizer` performing parameter search sweeps

### 7. Implement OverfittingDetector
- [x] Multi-timeframe parameters and out-of-sample sweeps verify model stability and reject overfit parameter sets

### 8. Create ReplayReportGenerator
- [x] Summary reports compile win rates, expectancy, net profits, and optimized parameter hashes

### 9. Add ReplayComparison
- [x] Backtests compare different strategy presets (e.g. Supertrend vs ADX-filtered) to select the optimal configuration

### 10. Document Replay Methodology
- [x] Documented in implementation guides and optimization rake task outputs

---

## Acceptance Criteria
- [x] Replay process calculates indicators and signals rapidly
- [x] Optimization searches identify robust parameter regimes
- [x] Expected performance metrics verify strategy viability
- [x] Overfitting analysis mitigates parameters drift across lookback windowsle

---

## Notes
- Replay uses SAME engine code as live (no simulation shortcuts)
- Data quality critical: gaps, corporate actions, corporate actions handled
- Parameter optimization on TRAIN only, test on TEST
- Walk-forward mimics real deployment (retrain monthly)
- Monte Carlo accounts for trade sequencing luck
- Replay is compute-intensive; run on dedicated worker
- Store replay results for LearningEngine (Phase 8)
- CI: nightly replay on last 30 days data