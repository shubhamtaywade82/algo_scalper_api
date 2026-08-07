# Milestone 4.1: Market Context Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Macro filter that decides if trading should be allowed.  
**Estimated Tasks:** 13

---

## Tasks

### 1. Implement MarketContextEngine
- [x] Create `app/engines/market_context_engine.rb`
- [x] Interface: `analyze(context) -> MarketContextOutput`
- [x] Input: `MarketContextInput` with:
  - `current_time`, `previous_close`, `pre_market_data`, `news_headlines`, `vix_level`, `expiry_today?`, `holiday_session?`
- [x] Output: `MarketContextOutput` with:
  - `decision`: `:allow_trading`, `:reduced_risk`, `:no_trade`
  - `context_score` (0-100)
  - `risk_multiplier` (0.5, 1.0, 1.5)
  - `reasons` (array of strings)
  - `flags` (array of symbols)

### 2. Add GapAnalyzer
- [x] Create `app/engines/analyzers/gap_analyzer.rb`
- [x] Calculate overnight gap: `(open - prev_close) / prev_close * 100`
- [x] Classify gap:
  - `gap_up_strong` (> 1.5%)
  - `gap_up_mild` (0.5% - 1.5%)
  - `flat` (-0.5% - 0.5%)
  - `gap_down_mild` (-1.5% - -0.5%)
  - `gap_down_strong` (< -1.5%)
- [x] Historical stats: gap fill probability by type
- [x] Adjust context score based on gap type and historical behavior

### 3. Implement OvernightNewsChecker
- [x] Create `app/engines/analyzers/overnight_news_checker.rb`
- [x] Placeholder for news API integration (future)
- [x] Current: check for scheduled events (RBI policy, Fed, earnings)
- [x] Keywords to monitor: "RBI", "Fed", "inflation", "GDP", "earnings", "merger"
- [x] Output: `news_risk_level` (:low, :medium, :high), `event_type`
- [x] Integrate with EventCalendar

### 4. Create IndiaVIXAnalyzer
- [x] Create `app/engines/analyzers/india_vix_analyzer.rb`
- [x] Fetch India VIX from NSE (via DhanHQ or direct)
- [x] VIX regimes:
  - `low_vol` (< 12): mean reversion favored
  - `normal_vol` (12-20): balanced
  - `high_vol` (20-30): trend following favored
  - `extreme_vol` (> 30): reduce risk / no trade
- [x] VIX trend: rising/falling (5-day slope)
- [x] VIX term structure: spot vs 1-month futures

### 5. Add ExpiryChecker
- [x] Create `app/engines/analyzers/expiry_checker.rb`
- [x] Detect: weekly expiry (Thursday), monthly expiry (last Thursday)
- [x] Expiry day rules:
  - No overnight positions
  - Reduced position size (50%)
  - No new entries after 14:00
  - Gamma scalping only for experienced strategies
- [x] Pre-expiry (Wed): reduced risk, avoid gamma-negative
- [x] Post-expiry (Fri): normal rules resume

### 6. Implement EventCalendar
- [x] Create `app/engines/analyzers/event_calendar.rb`
- [x] Static calendar: RBI policy dates, Fed meetings, budget, elections
- [x] Dynamic: corporate earnings (NIFTY 50 stocks)
- [x] Methods:
  - `events_today` - array of events
  - `events_this_week` - array
  - `high_impact_today?` - boolean
  - `blackout_periods` - times to avoid trading
- [x] Source: JSON file updated monthly, API for earnings

### 7. Create HolidaySessionDetector
- [x] Create `app/engines/analyzers/holiday_session_detector.rb`
- [x] Use `ExchangeCalendar` from Milestone 1.3
- [x] Detect: full holiday, half-day (Muhurat trading), pre-holiday session
- [x] Adjust: reduced liquidity expected, wider spreads
- [x] Output: `session_type`, `liquidity_expectation`, `risk_adjustment`

### 8. Add PreviousDayTrendAnalyzer
- [x] Create `app/engines/analyzers/previous_day_trend_analyzer.rb`
- [x] Analyze previous day: trend (up/down/sideways), range, volume, close position
- [x] Overnight bias: gap direction vs previous trend
- [x] Key levels: previous day high, low, close, VWAP
- [x] Output: `prev_trend`, `key_levels`, `overnight_bias`

### 9. Implement MarketOpenAnalyzer
- [x] Create `app/engines/analyzers/market_open_analyzer.rb`
- [x] First 30 minutes (9:15-9:45) behavior
- [x] Metrics: opening range, volume vs average, breadth (advance/decline)
- [x] Opening types: trend day, range day, reversal day, neutral
- [x] Output: `opening_type`, `or_high`, `or_low`, `volume_ratio`, `bias`

### 10. Create ContextScoreCalculator
- [x] Create `app/engines/calculators/context_score_calculator.rb`
- [x] Weighted scoring:
  - Gap analysis: 20%
  - VIX regime: 25%
  - Event risk: 15%
  - Expiry adjustment: 15%
  - Session type: 10%
  - Previous trend: 10%
  - Market open: 5%
- [x] Score 0-100, map to decision:
  - > 80: `:allow_trading` (risk_multiplier 1.0)
  - 50-80: `:reduced_risk` (risk_multiplier 0.5)
  - < 50: `:no_trade` (risk_multiplier 0.0)

### 11. Add Output Enum Definition
- [x] Define `MarketContextDecision` enum/module:
  ```ruby
  module MarketContextDecision
    ALLOW_TRADING = :allow_trading
    REDUCED_RISK = :reduced_risk
    NO_TRADE = :no_trade
  end
  ```
- [x] Used by RiskValidationEngine and Strategy layer

### 12. Write Tests for Each Context Rule
- [x] Create `spec/engines/market_context_engine_spec.rb`
- [x] Test cases:
  - Strong gap up + high VIX = reduced_risk
  - RBI policy day = no_trade (if high impact)
  - Expiry day Thursday = reduced_risk
  - Holiday session = reduced_risk
  - Normal day, low VIX, no events = allow_trading
  - Extreme VIX (>35) = no_trade
  - Pre-market gap down > 2% = reduced_risk

### 13. Add Integration Test with Real Market Data
- [x] Create `spec/integration/market_context_integration_spec.rb`
- [x] Use recorded market data (ticks, VIX, news)
- [x] Verify engine decisions match manual analysis
- [x] Test across different market regimes (bull, bear, sideways)
- [x] Performance: analysis completes in < 50ms

---

## Acceptance Criteria
- [x] Engine returns decision in < 50ms
- [x] All 9 analyzers integrated and tested
- [x] Context score calculation matches weighted formula
- [x] Decision enum used consistently across system
- [x] Expiry day rules enforced correctly
- [x] Event calendar loads and detects high-impact days
- [x] Integration test passes on 30 days of historical data
- [x] No trade signals generated when decision = :no_trade

---

## Notes
- This is the FIRST gate - nothing proceeds if decision = :no_trade
- Context score feeds into Trade Scoring Engine as component
- Risk multiplier applies to position sizing in RiskValidationEngine
- News checker is placeholder; integrate real API in Phase 7+
- Cache VIX and event data in Redis (TTL: 1 hour)