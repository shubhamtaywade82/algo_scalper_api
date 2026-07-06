# Milestone 8.2: Performance Analytics

**Phase:** 8 — Learning & Optimization  
**Goal:** Deep metrics on strategy and execution quality.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement PerformanceEngine
- [x] Implemented inside `Ai::Autonomous::Auditor` and `PositionTracker.paper_trading_stats_with_pct`
- [x] Supports symbol filtering, day lookbacks, and calculates win rates, gross profit/loss, and max drawdown

### 2. Add WinRateCalculator
- [x] Implemented via DB aggregate counts (`winners.to_f / total * 100`) inside `Auditor#performance_stats`

### 3. Implement ProfitFactorCalculator
- [x] Implemented via `Auditor#calculate_profit_factor` dividing gross profit by absolute gross loss

### 4. Create SharpeRatioCalculator
- [x] Annualized Sharpe ratios calculated inside indicator optimizations and backtest summaries

### 5. Add SortinoRatioCalculator
- [x] Evaluated during optimization runs using downside deviation profiles of historical returns

### 6. Implement CalmarRatioCalculator
- [x] Integrated inside backtest report summaries comparing returns vs peak-to-trough drawdowns

### 7. Create DrawdownAnalyzer
- [x] Implemented via `Auditor#calculate_drawdown` using sequential iteration over closed positions

### 8. Add ConsecutiveLossAnalyzer
- [x] Tracks consecutive wins and losses to activate safety limits (e.g., stopping trading after 3 consecutive losing days)

### 9. Implement ExpectancyCalculator
- [x] Implemented inside `OptionsBuying::PerformanceDb` to calculate rolling expectancy (win rate * avg win - loss rate * avg loss)

### 10. Create PerformanceDashboardData Endpoint
- [x] Implemented inside `Api::DashboardController` serving open/closed positions, live PnL, and health status

### 11. Add BenchmarkComparison
- [x] Backtests compare strategy returns against direct index price movements to measure alpha/beta outperformance

### 12. Write Tests with Known Performance Scenarios
- [x] Verified via RSpec specs covering the `Auditor` metrics calculations and optimizer calculations

---

## Acceptance Criteria
- [x] Performance metrics computed mathematically correctly
- [x] Auditor generates statistics in < 100ms
- [x] Dashboard endpoint serves complete metrics
- [x] Drawdown math matches manual peak-to-trough calculations
- [x] Backtests generate clear return and win rate statistics
- [x] Tests cover the audit calculations successfullyes

---

## Notes
- Performance metrics computed from closed trades only (no unrealized)
- Daily returns: sum of trade P&L per day / starting capital
- Risk-free rate: configurable, default 7% (India 10Y)
- Minimum trades for significance: 30 (win rate), 100 (Sharpe)
- Equity curve stored in `performance_snapshots` table (daily)
- Dashboard uses this data for real-time charts
- Benchmark data: fetch NIFTY 50 daily closes from historical API