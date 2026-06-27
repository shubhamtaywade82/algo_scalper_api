# Milestone 6.1: Risk Validation Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Nothing reaches execution without passing risk rules.  
**Estimated Tasks:** 16

---

## Tasks

### 1. Implement RiskValidationEngine
- [x] Integrated inside `Entries::EntryGuardPipeline`
- [x] Checks entry signal and metadata through sequential guard chain
- [x] Output structure returns `:pass` or blocked details

### 2. Add DailyLossLimitChecker
- [x] Implemented as `Entries::Guards::DailyLimitsGuard`
- [x] Configurable daily limits and budget allocation rules

### 3. Add WeeklyLossLimitChecker
- [x] Integrated via `DailyLimitsGuard` budget schedules

### 4. Add MonthlyLossLimitChecker
- [x] Integrated via global account drawdown/loss rules

### 5. Implement MaxOpenPositionsChecker
- [x] Implemented as `Entries::Guards::MaxConcurrentGuard` and `GlobalMaxConcurrentGuard`
- [x] Validates total open positions < limits (per index and global)

### 6. Add MarginAvailabilityChecker
- [x] Implemented as `Entries::Guards::SizingGuard` using cash balance
- [x] Affordability checks prevent over-allocation

### 7. Implement RiskPerTradeCalculator
- [x] Implemented inside `Trading::CapitalAllocator` and `Capital::Allocator`
- [x] Calculates risk budget based on stop loss distance

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
- [x] Implemented as `Entries::Guards::TradingTimeRestrictionGuard` and `EarliestEntryGuard`
- [x] Checks session start and intraday cutoff windows

### 11. Implement ExpiryRuleChecker
- [x] Implemented as `Entries::Guards::WeeklyExpiryGuard` and `ExpiryWeekPowerTrendGuard`

### 12. Add RewardRiskRatioChecker
- [x] Implemented as `Entries::Guards::RiskPolicyGuard`

### 13. Create CorrelationChecker
- [x] Implemented via `Entries::Guards::ExposureGuard` max same side rules

### 14. Implement RiskEvent Logging
- [x] Logged to database signals and console alerts via loggerne

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