# Milestone 6.1: Risk Validation Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Nothing reaches execution without passing risk rules.  
**Estimated Tasks:** 16

---

## Tasks

### 1. Implement RiskValidationEngine
- [ ] Create `app/engines/risk_validation_engine.rb`
- [ ] Interface: `validate(input) -> RiskValidationOutput`
- [ ] Input: `RiskValidationInput` with:
  - `trade_score` (from TradeScoringEngine)
  - `proposed_order` (instrument, side, qty, price, strike, expiry)
  - `account_state` (capital, open positions, daily P&L)
  - `market_conditions` (liquidity, regime, volatility)
- [ ] Output: `RiskValidationOutput` with:
  - `approved` (boolean)
  - `approved_quantity` (may be reduced)
  - `risk_metrics` (position size, margin req, risk %)
  - `violations` (array of failed checks)
  - `warnings` (array)
  - `emergency_stop` (boolean)

### 2. Add DailyLossLimitChecker
- [ ] Create `app/engines/risk/checkers/daily_loss_limit_checker.rb`
- [ ] Config: `max_daily_loss_rupees` (e.g., 50,000)
- [ ] Track: realized + unrealized P&L for current day
- [ ] Check: `(daily_pnl + proposed_risk) > -max_daily_loss`
- [ ] If violated: reject all new trades, allow exits only
- [ ] Reset at market close (15:30)
- [ ] Output: `passed`, `current_pnl`, `remaining_risk_budget`, `limit`

### 3. Add WeeklyLossLimitChecker
- [ ] Create `app/engines/risk/checkers/weekly_loss_limit_checker.rb`
- [ ] Config: `max_weekly_loss_rupees` (e.g., 150,000)
- [ ] Rolling 5-trading-day window (Mon-Fri)
- [ ] Track daily P&L in Redis with TTL 7 days
- [ ] Check: sum of last 5 days P&L > -max_weekly_loss
- [ ] Stricter than daily: reduces position sizing progressively
- [ ] Output: `passed`, `weekly_pnl`, `remaining_budget`, `days_in_window`

### 4. Add MonthlyLossLimitChecker
- [ ] Create `app/engines/risk/checkers/monthly_loss_limit_checker.rb`
- [ ] Config: `max_monthly_loss_rupees` (e.g., 500,000)
- [ ] Calendar month (1st to last trading day)
- [ ] Circuit breaker: if monthly loss > 50% of limit, halve all position sizes
- [ ] If > 75%: stop new entries, only exits
- [ ] Output: `passed`, `monthly_pnl`, `risk_reduction_factor`

### 5. Implement MaxOpenPositionsChecker
- [ ] Create `app/engines/risk/checkers/max_open_positions_checker.rb`
- [ ] Config per index: `max_positions_nifty: 3`, `max_positions_banknifty: 2`
- [ ] Config total: `max_total_positions: 5`
- [ ] Check: current open positions < limits
- [ ] Count: each strike/expiry = 1 position (even if multi-leg)
- [ ] Output: `passed`, `current_counts`, `limits`

### 6. Add MarginAvailabilityChecker
- [ ] Create `app/engines/risk/checkers/margin_availability_checker.rb`
- [ ] Call `FundsService.available_margin`
- [ ] Required margin: `MarginCalculatorService.estimate(order)`
- [ ] Buffer: require 20% free margin above requirement
- [ ] Check: `available_margin > required_margin * 1.2`
- [ ] Output: `passed`, `available`, `required`, `buffer`, `utilization_pct`

### 7. Implement RiskPerTradeCalculator
- [ ] Create `app/engines/risk/calculators/risk_per_trade_calculator.rb`
- [ ] Config: `max_risk_per_trade_pct` (e.g., 1.5% of capital)
- [ ] Risk = `quantity * |entry - stop_loss| * lot_size`
- [ ] Capital = available margin + unrealized P&L
- [ ] Max quantity = `max_risk / risk_per_lot`
- [ ] Output: `max_quantity`, `risk_per_lot`, `risk_pct`, `capital_base`

### 8. Add PositionSizingCalculator
- [x] Integrated inside `Capital::Allocator` (queries `OptionsBuying::PerformanceDb` for historical win rate and payout ratios)
- [x] Methods:
  - Fixed fractional: standard capital allocation
  - Kelly criterion variant: `p - (1-p)/r` (capped at max_capital_allocation_pct)
  - Volatility/Decay-adjusted sizing
- [x] Config: `kelly_sizing.enabled` in `config/algo.yml`
- [x] Min/max bounds: lot-aligned constraints, safety caps, affordability check

### 9. Implement MaxExposureChecker
- [x] Integrated inside `Entries::Guards::ExposureGuard` to check rupee-based limits
- [x] Per index: configurable limits in `config/algo.yml` (e.g. NIFTY: 500,000, BANKNIFTY: 300,000)
- [x] Exposure calculated as sum of `quantity * entry_price` for open positions
- [x] Proposed exposure + current exposure < limit
- [x] Pipeline re-ordered so SizingGuard runs before ExposureGuard, exposing proposed quantity

### 10. Add TimeFilterChecker
- [ ] Create `app/engines/risk/checkers/time_filter_checker.rb`
- [ ] No new entries before 09:20 (let opening range form)
- [ ] No new entries after 15:15 (intraday close window)
- [ ] Expiry day: no entries after 14:00
- [ ] Pre-market (09:00-09:15): data collection only
- [ ] Configurable per environment
- [ ] Output: `passed`, `current_time`, `window`, `reason`

### 11. Implement ExpiryRuleChecker
- [ ] Create `app/engines/risk/checkers/expiry_rule_checker.rb`
- [ ] No overnight positions on expiry day (Thursday)
- [ ] Intraday only on expiry
- [ ] Reduced position size (50%) on expiry day
- [ ] No new entries 1 hour before expiry (14:30)
- [ ] Weekly vs monthly expiry different rules
- [ ] Output: `passed`, `is_expiry_day`, `rules_applied`, `size_multiplier`

### 12. Add RewardRiskRatioChecker
- [ ] Create `app/engines/risk/checkers/reward_risk_ratio_checker.rb`
- [ ] Minimum R:R: 2:1 (configurable)
- [ ] Reward = `|target - entry| * qty * lot_size`
- [ ] Risk = `|entry - stop_loss| * qty * lot_size`
- [ ] Use primary target (first target) for calculation
- [ ] Output: `passed`, `reward`, `risk`, `ratio`, `minimum`

### 13. Create CorrelationChecker
- [ ] Create `app/engines/risk/checkers/correlation_checker.rb`
- [ ] Check: proposed position correlates with existing
- [ ] Same underlying + same direction = concentration risk
- [ ] Same expiry + adjacent strikes = gamma concentration
- [ ] Limit: max 2 positions same direction per underlying
- [ ] Output: `passed`, `correlated_positions`, `concentration_score`

### 14. Implement RiskEvent Logging
- [ ] Create `app/engines/risk/risk_event_logger.rb`
- [ ] Log every risk check result to `risk_events` table
- [ ] Event types: `check_passed`, `check_failed`, `limit_breached`, `emergency_stop`
- [ ] Include: timestamp, check name, input values, result, context
- [ ] Alert on: limit breaches, emergency stops
- [ ] Dashboard: risk event timeline

### 15. Add EmergencyStop
- [ ] Create `app/engines/risk/emergency_stop.rb`
- [ ] Triggers:
  - Daily loss limit hit
  - Weekly loss limit hit
  - Monthly loss > 75% limit
  - System error (data feed down, broker disconnect)
  - Manual activation via API
- [ ] Actions:
  - Cancel all pending orders
  - Close all positions at market (configurable)
  - Block all new trade validation
  - Alert via Telegram/Email
  - Require manual reset (admin API)
- [ ] State persisted in Redis (survives restart)

### 16. Write Tests for Each Risk Rule
- [ ] Create `spec/engines/risk_validation_engine_spec.rb`
- [ ] Test each checker in isolation with boundary values
- [ ] Test combinations: daily + weekly + monthly limits
- [ ] Test position sizing with different methods
- [ ] Test emergency stop triggers and blocks new trades
- [ ] Test expiry day rules
- [ ] Test correlation detection
- [ ] Integration: full validation pipeline with mock account state

---

## Acceptance Criteria
- [ ] Engine validates trade in < 15ms
- [ ] All 12 checkers integrated and tested
- [ ] Daily/weekly/monthly limits enforce correctly
- [ ] Position sizing respects all constraints
- [ ] Emergency stop activates and blocks trades
- [ ] Risk events logged for audit trail
- [ ] Margin checks use real broker data
- [ ] Expiry rules prevent overnight risk
- [ ] Correlation checker prevents concentration

---

## Notes
- Risk engine runs AFTER Trade Scoring Engine (score >= threshold)
- Hard gate: any checker fails = trade rejected
- Soft gate: warnings logged but trade allowed (configurable)
- Limits configurable per environment (paper vs live)
- Emergency stop state must survive process restart
- Consider:3 restart
- Position sizing uses Kelly with 2% cap for safety