# Milestone 10.3: Historical Replay & Walk-Forward Testing

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Validate strategies on historical data before deployment.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement HistoricalReplayEngine
- [ ] Create `app/engines/historical_replay_engine.rb`
- [ ] Interface: `replay(config) -> ReplayResult`
- [ ] Config:
  - `start_date`, `end_date`
  - `instruments` (underlyings)
  - `speed` (1x, 10x, 100x, max)
  - `engines` (which to run)
  - `strategies` (which to test)
- [ ] Tick-by-tick replay from `market_ticks` hypertable
- [ ] EventBus publishes same events as live
- [ ] Engines process exactly as live

### 2. Create ReplaySpeedController
- [ ] Create `app/engines/replay_speed_controller.rb`
- [ ] 1x: real-time (for debugging)
- [ ] 10x: fast (1 day in ~2 hours)
- [ ] 100x: very fast (1 day in ~15 min)
- [ ] Max: as fast as possible (for full backtest)
- [ ] Throttle: respect engine processing time
- [ ] Pause/resume/seek API

### 3. Add ReplayMetricsCollector
- [ ] Create `app/engines/replay_metrics_collector.rb`
- [ ] Collects during replay:
  - Engine outputs at each step
  - Strategy signals generated
  - Trade scores, risk checks
  - Execution simulated (paper broker)
  - P&L, MFE, MAE per trade
- [ ] Stores in temporary tables or Redis
- [ ] Output: `ReplayMetrics` for report generation

### 4. Implement WalkForwardTestRunner
- [ ] Create `app/engines/walk_forward_test_runner.rb`
- [ ] Rolling window methodology:
  - Train window: 6 months
  - Test window: 1 month
  - Step: 1 month
  - Example: Train Jan-Jun, Test Jul; Train Feb-Jul, Test Aug
- [ ] For each fold: optimize parameters on train, test on test
- [ ] Aggregates: out-of-sample performance across folds
- [ ] Detects: overfitting (train >> test performance)

### 5. Create MonteCarloSimulator
- [ ] Create `app/engines/monte_carlo_simulator.rb`
- [ ] Resample trades with replacement (10,000 iterations)
- [ ] Metrics per iteration: expectancy, max DD, Sharpe
- [ ] Output: confidence intervals for all metrics
- [ ] Stress test: randomize trade order, exit timing
- [ ] Ruin probability: % paths where DD > max allowed

### 6. Add ParameterOptimization
- [ ] Create `app/engines/parameter_optimization.rb`
- [ ] Grid search over parameter ranges:
  - EMA periods, ADX thresholds, volume multipliers
  - Score thresholds, position sizing params
- [ ] Bayesian optimization (optional): `rbayes` gem
- [ ] Objective: maximize expectancy, minimize max DD
- [ ] Constraints: min trades, max params
- [ ] Output: Pareto frontier of parameter sets

### 7. Implement OverfittingDetector
- [ ] Create `app/engines/overfitting_detector.rb`
- [ ] Compare: in-sample vs out-of-sample performance
- [ ] Metrics:
  - Performance degradation ratio (OOS/IS)
  - Parameter stability across folds
  - Number of parameters vs trades (degrees of freedom)
- [ ] Rules:
  - Degradation > 50% = overfit
  - Parameters change wildly across folds = overfit
  - Params/trades > 1/10 = overfit risk

### 8. Create ReplayReportGenerator
- [ ] Create `app/engines/replay_report_generator.rb`
- [ ] Report includes:
  - Equity curve (cumulative P&L)
  - Drawdown chart
  - Monthly/weekly returns table
  - Strategy comparison (if multiple)
  - Parameter sensitivity heatmap
  - Walk-forward analysis summary
  - Monte Carlo confidence intervals
- [ ] Format: HTML (viewable), JSON (programmatic), PDF (archive)
- [ ] Save to `replay_reports` table

### 9. Add ReplayComparison
- [ ] Create `app/engines/replay_comparison.rb`
- [ ] Compare: Strategy A vs Strategy B vs Ensemble
- [ ] Statistical tests: t-test on returns, Sharpe difference
- [ ] Correlation: strategy returns correlation matrix
- [ ] Diversification benefit: ensemble vs best single
- [ ] Output: recommendation (deploy A, B, both, neither)

### 10. Document Replay Methodology
- [ ] Create `docs/replay.md` with:
  - Data requirements (ticks, chains, depth)
  - Replay architecture
  - Walk-forward design
  - Parameter optimization protocol
  - Overfitting detection criteria
  - Report interpretation guide
  - CI integration: nightly replay on recent data

---

## Acceptance Criteria
- [ ] Replay engine processes 1M ticks in < 30 min at 100x
- [ ] Walk-forward produces stable out-of-sample metrics
- [ ] Monte Carlo gives 95% CI on expectancy
- [ ] Parameter optimization finds robust regions (not points)
- [ ] Overfitting detector flags known overfit strategies
- [ ] Reports generated automatically with all charts
- [ ] Comparison tool validates ensemble benefit
- [ ] Methodology documented and reproducible

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