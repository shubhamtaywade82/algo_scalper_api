# Milestone 8.2: Performance Analytics

**Phase:** 8 — Learning & Optimization  
**Goal:** Deep metrics on strategy and execution quality.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement PerformanceEngine
- [ ] Create `app/engines/performance_engine.rb`
- [ ] Interface: `report(time_window, filters) -> PerformanceReport`
- [ ] Filters: strategy, regime, instrument, date range, expiry proximity
- [ ] Time windows: daily, weekly, monthly, quarterly, all-time
- [ ] Output: comprehensive performance metrics object

### 2. Add WinRateCalculator
- [ ] Create `app/engines/performance/calculators/win_rate_calculator.rb`
- [ ] Win rate = wins / (wins + losses) * 100
- [ ] Statistical significance: Wilson score interval
- [ ] Minimum sample: 30 trades
- [ ] By: strategy, regime, time, delta, expiry
- [ ] Output: `win_rate`, `confidence_interval`, `sample_size`

### 3. Implement ProfitFactorCalculator
- [ ] Create `app/engines/performance/calculators/profit_factor_calculator.rb`
- [ ] Profit Factor = gross_profit / gross_loss
- [ ] PF > 1.0 = profitable, > 1.5 = good, > 2.0 = excellent
- [ ] By strategy, regime, time window
- [ ] Handle edge case: zero gross loss (return large number)

### 4. Create SharpeRatioCalculator
- [ ] Create `app/engines/performance/calculators/sharpe_ratio_calculator.rb`
- [ ] Daily returns series from trade P&L
- [ ] Sharpe = (mean_daily_return - risk_free) / std_daily_return * sqrt(252)
- [ ] Risk-free: 7% annual (Indian 10Y govt bond approx)
- [ ] Rolling Sharpe (30-day, 90-day)
- [ ] Output: `sharpe`, `annualized_return`, `annualized_vol`

### 5. Add SortinoRatioCalculator
- [ ] Create `app/engines/performance/calculators/sortino_ratio_calculator.rb`
- [ ] Downside deviation only (returns < target)
- [ ] Target: 0% or risk-free rate
- [ ] Better for skewed return distributions
- [ ] Output: `sortino`, `downside_deviation`

### 6. Implement CalmarRatioCalculator
- [ ] Create `app/engines/performance/calculators/calmar_ratio_calculator.rb`
- [ ] Calmar = annualized_return / max_drawdown
- [ ] Max drawdown from equity curve peak
- [ ] Measures return per unit of worst drawdown
- [ ] Output: `calmar`, `max_drawdown`, `drawdown_duration`

### 7. Create DrawdownAnalyzer
- [ ] Create `app/engines/performance/analyzers/drawdown_analyzer.rb`
- [ ] Equity curve from cumulative P&L
- [ ] Metrics:
  - Max drawdown (peak to trough)
  - Max drawdown duration (days to recover)
  - Current drawdown
  - Drawdown frequency and depth distribution
  - Ulcer Index (RMS of drawdowns)
- [ ] Visualization data: drawdown periods for charts

### 8. Add ConsecutiveLossAnalyzer
- [ ] Create `app/engines/performance/analyzers/consecutive_loss_analyzer.rb`
- [ ] Streak analysis: max consecutive wins/losses
- [ ] Current streak
- [ ] Probability of n consecutive losses (binomial)
- [ ] Kelly criterion adjustment for streak risk
- [ ] Alert if current streak > 95th percentile

### 9. Implement ExpectancyCalculator
- [ ] Create `app/engines/performance/calculators/expectancy_calculator.rb`
- [ ] Expectancy per trade = `(win_rate * avg_win) - (loss_rate * avg_loss)`
- [ ] Expectancy per rupee risked = expectancy / avg_risk
- [ ] By strategy, regime, time window
- [ ] Confidence intervals via bootstrap
- [ ] Minimum expectancy threshold for strategy viability

### 10. Create PerformanceDashboardData Endpoint
- [ ] Create `app/controllers/api/v1/performance_controller.rb`
- [ ] `GET /api/v1/performance?window=weekly&strategy=orb`
- [ ] Response: all metrics + equity curve data + drawdown periods
- [ ] Real-time: update on each trade close
- [ ] Cached: 5 min TTL for historical windows

### 11. Add BenchmarkComparison
- [ ] Create `app/engines/performance/benchmark_comparison.rb`
- [ ] Compare strategy returns vs:
  - NIFTY 50 (buy & hold)
  - NIFTY 50 + protective put (hedged)
  - Risk-free rate
- [ ] Alpha = strategy_return - benchmark_return
- [ ] Beta = covariance(strategy, benchmark) / variance(benchmark)
- [ ] Information ratio = alpha / tracking_error

### 12. Write Tests with Known Performance Scenarios
- [ ] Create `spec/engines/performance_engine_spec.rb`
- [ ] Fixtures: equity curves with known metrics
- [ ] Test cases:
  - Perfect strategy: 100% win rate, PF = inf
  - Losing strategy: 40% win rate, PF = 0.8
  - High volatility: Sharpe < 1, Sortino > Sharpe
  - Deep drawdown: Calmar < 1
  - Streak analysis matches manual count
  - Benchmark comparison math verified
- [ ] Property tests: PF = gross_profit/gross_loss, Sharpe formula

---

## Acceptance Criteria
- [ ] All 8 calculators produce mathematically correct results
- [ ] PerformanceEngine generates report in < 500ms
- [ ] Dashboard endpoint returns complete metrics
- [ ] Statistical confidence intervals accurate
- [ ] Drawdown analysis matches manual calculation
- [ ] Benchmark comparison shows alpha/beta correctly
- [ ] Metrics feed into LearningEngine for optimization
- [ ] All tests pass with reference equity curves

---

## Notes
- Performance metrics computed from closed trades only (no unrealized)
- Daily returns: sum of trade P&L per day / starting capital
- Risk-free rate: configurable, default 7% (India 10Y)
- Minimum trades for significance: 30 (win rate), 100 (Sharpe)
- Equity curve stored in `performance_snapshots` table (daily)
- Dashboard uses this data for real-time charts
- Benchmark data: fetch NIFTY 50 daily closes from historical API