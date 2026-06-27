# Milestone 8.1: Learning Engine

**Phase:** 8 — Learning & Optimization  
**Goal:** Continuous improvement from every trade.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement LearningEngine
- [ ] Create `app/engines/learning_engine.rb`
- [ ] Interface: `record(trade)` and `analyze(time_window)`
- [ ] Trigger: after every trade closes (callback)
- [ ] Scheduled: daily, weekly, monthly analysis jobs
- [ ] Stores results in `learning_records` table

### 2. Add TradeRecorder
- [ ] Create `app/engines/learning/trade_recorder.rb`
- [ ] Capture at entry:
  - All engine outputs (context, regime, structure, momentum, liquidity, option_intel)
  - Strike selection details (scores, alternatives)
  - Trade score breakdown
  - Risk metrics (position size, R:R, margin)
  - Account state (capital, open positions, daily P&L)
- [ ] Capture at exit:
  - Exit price, time, reason
  - All engine outputs at exit
  - MFE, MAE, holding time
  - Slippage, fees
- [ ] Store in `trade_features` and `trades` tables

### 3. Implement MFECalculator
- [ ] Create `app/engines/learning/calculators/mfe_calculator.rb`
- [ ] Maximum Favorable Excursion:
  - Track tick-by-tick from entry to exit
  - MFE = max(`(high - entry)` for long, `(entry - low)` for short) * qty * lot_size
  - MFE % = MFE / risk_amount * 100
- [ ] Time to MFE: when during trade did MFE occur
- [ ] Store per trade for analysis

### 4. Implement MAECalculator
- [ ] Create `app/engines/learning/calculators/mae_calculator.rb`
- [ ] Maximum Adverse Excursion:
  - MAE = max(`(entry - low)` for long, `(high - entry)` for short) * qty * lot_size
  - MAE % = MAE / risk_amount * 100
- [ ] Time to MAE
- [ ] MAE/MFE ratio: measure of trade efficiency

### 5. Add SlippageAnalyzer
- [ ] Create `app/engines/learning/analyzers/slippage_analyzer.rb`
- [ ] Expected vs actual fill price
- [ ] Slippage components: spread cost, market impact, timing
- [ ] By: instrument, time of day, order size, volatility
- [ ] Alert if avg slippage > 3 bps

### 6. Create HoldingTimeAnalyzer
- [ ] Create `app/engines/learning/analyzers/holding_time_analyzer.rb`
- [ ] Distribution of holding times by outcome
- [ ] Optimal holding time per strategy/regime
- [ ] Time-based exit analysis: early exit vs hold to target
- [ ] Expiry proximity effect on holding time

### 7. Implement OutcomeClassifier
- [ ] Create `app/engines/learning/classifiers/outcome_classifier.rb`
- [ ] Classify: `win` (net > 0), `loss` (net < 0), `breakeven` (|net| < fees)
- [ ] R-multiple: `net_pnl / risk_amount`
- [ ] Win/loss by: strategy, regime, time of day, delta range, expiry day
- [ ] Store in `learning_records`

### 8. Add RegimePerformanceAnalyzer
- [ ] Create `app/engines/learning/analyzers/regime_performance_analyzer.rb`
- [ ] Win rate, expectancy, avg RR by regime type
- [ ] Regime transition performance (trending→ranging, etc.)
- [ ] Best/worst regimes per strategy
- [ ] Regime persistence vs trade duration alignment

### 9. Create TimeOfDayAnalyzer
- [ ] Create `app/engines/learning/analyzers/time_of_day_analyzer.rb`
- [ ] Session slices: 9:15-10:00, 10:00-11:30, 11:30-13:00, 13:00-14:30, 14:30-15:15
- [ ] Performance metrics per slice
- [ ] Identify: best/worst trading hours
- [ ] Volume/liquidity correlation

### 10. Implement DeltaRangeAnalyzer
- [ ] Create `app/engines/learning/analyzers/delta_range_analyzer.rb`
- [ ] Performance by entry delta buckets: 0.2-0.3, 0.3-0.4, 0.4-0.5, 0.5-0.6, 0.6-0.7
- [ ] Optimal delta range per strategy
- [ ] Delta decay effect (delta change during hold)

### 11. Add ExpiryDayAnalyzer
- [ ] Create `app/engines/learning/analyzers/expiry_day_analyzer.rb`
- [ ] Performance: expiry day vs non-expiry
- [ ] Weekly vs monthly expiry
- [ ] Days to expiry buckets: 0 (0DTE), 1-2, 3-5, 6+
- [ ] Gamma/theta dynamics near expiry

### 12. Create StrategyExpectancyCalculator
- [ ] Create `app/engines/learning/calculators/strategy_expectancy_calculator.rb`
- [ ] Expectancy = `(win_rate * avg_win) - (loss_rate * avg_loss)`
- [ ] Per strategy, per regime, per time window
- [ ] Statistical significance: minimum 30 trades
- [ ] Rolling expectancy (last 100 trades)
- [ ] Alert if expectancy turns negative

### 13. Implement LearningReportGenerator
- [ ] Create `app/engines/learning/learning_report_generator.rb`
- [ ] Weekly report (Monday 9 AM):
  - Strategy performance table
  - Regime performance heatmap
  - Time-of-day analysis
  - Delta/expiry insights
  - Top 3 improvements
- [ ] Monthly report: deeper statistical analysis
- [ ] Format: JSON for dashboard, Markdown for email/Telegram
- [ ] Store in `learning_reports` table

### 14. Write Tests with Synthetic Trade Histories
- [ ] Create `spec/engines/learning_engine_spec.rb`
- [ ] Fixtures: trade sequences with known patterns
- [ ] Test MFE/MAE calculation accuracy
- [ ] Test expectancy math with known win rates
- [ ] Test regime performance grouping
- [ ] Test report generation format
- [ ] Property tests: expectancy = win_rate * avg_win - loss_rate * avg_loss

---

## Acceptance Criteria
- [ ] LearningEngine records every trade automatically
- [ ] MFE/MAE calculated tick-accurate
- [ ] Slippage analysis identifies execution issues
- [ ] Regime performance shows actionable insights
- [ ] Time-of-day analysis reveals optimal hours
- [ ] Delta range analysis guides strike selection
- [ ] Expiry day analysis prevents expiry-day losses
- [ ] Strategy expectancy tracked with statistical rigor
- [ ] Weekly reports generated and delivered
- [ ] All tests pass with synthetic data

---

## Notes
- Learning runs AFTER trade closes (no look-ahead bias)
- Minimum sample sizes: 30 trades for statistical significance
- Results feed back into: strategy weights, score thresholds, position sizing
- Vector store (Phase 7.3) enables similarity-based learning
- Consider: online learning (update after each trade) vs batch
- Privacy: no PII in learning records
- Alert on: negative expectancy, regime performance degradation