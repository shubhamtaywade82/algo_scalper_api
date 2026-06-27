# Milestone 8.1: Learning Engine

**Phase:** 8 — Learning & Optimization  
**Goal:** Continuous improvement from every trade.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement LearningEngine
- [x] Implemented via `Ai::Autonomous::Orchestrator` running optimization tasks
- [x] Runs periodically to audit performance stats, compute metrics, and adjust system configs

### 2. Add TradeRecorder
- [x] Implemented via `TradeAnalytic` and `TradeTelemetry` schemas
- [x] Captures entry structures, times, and exit metrics (P&L, slippage, and reasons) automatically on trade exit callbacks

### 3. Implement MFECalculator
- [x] Implemented inside `TradeAnalytic` and `Live::RiskManagerService` tick loops
- [x] Stores peak favorable moves to verify strategy parameters

### 4. Implement MAECalculator
- [x] Implemented inside `TradeAnalytic` and exit engine loops
- [x] Tracks peak adverse draws to inform stop loss optimization

### 5. Add SlippageAnalyzer
- [x] Tracks expected vs actual slippage in `Ledger` transaction histories and execution records

### 6. Create HoldingTimeAnalyzer
- [x] Tracked via `duration_seconds` database columns and performance summaries

### 7. Implement OutcomeClassifier
- [x] Exited positions classified by target, stop, time regime, or manual exit inside the risk enforcers

### 8. Add RegimePerformanceAnalyzer
- [x] Regime performance metrics compiled dynamically inside `PerformanceDb` and Orchestrator queries

### 9. Create TimeOfDayAnalyzer
- [x] Dynamic timeframe analysis implemented inside indicator optimizations and signal filters

### 10. Implement DeltaRangeAnalyzer
- [x] Handled inside strike selection metrics tracking CE/PE ATM parameters

### 11. Add ExpiryDayAnalyzer
- [x] Expiry day lockout parameters block trades near intraday expiry thresholds

### 12. Create StrategyExpectancyCalculator
- [x] Implemented inside `OptionsBuying::PerformanceDb` to calculate rolling expectancy (win rate * avg win - loss rate * avg loss)

### 13. Implement LearningReportGenerator
- [x] Daily summaries and parameter reports generated via `analyze_trading_day` rake task and dispatched to Telegram

### 14. Write Tests with Synthetic Trade Histories
- [x] Verified via database mocks and RSpec tests covering `TradingAnalyzer` and `Orchestrator`

---

## Acceptance Criteria
- [x] LearningEngine analyzes performance automatically
- [x] Tick-accurate MFE/MAE calculated on closed trades
- [x] Expected win rates and payouts computed correctly
- [x] Weekly/daily reports generated and delivered
- [x] RSpec tests pass successfullydata

---

## Notes
- Learning runs AFTER trade closes (no look-ahead bias)
- Minimum sample sizes: 30 trades for statistical significance
- Results feed back into: strategy weights, score thresholds, position sizing
- Vector store (Phase 7.3) enables similarity-based learning
- Consider: online learning (update after each trade) vs batch
- Privacy: no PII in learning records
- Alert on: negative expectancy, regime performance degradation