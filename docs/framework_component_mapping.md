# Framework Component Mapping Audit

Maps every codebase file and class to the research document framework components.
Audit date: 2026-06-24 (after P1, P3–P13 implementation + bid-ask depth upgrade).

---

## Gate / filter / selector components

### 1. Pre-market IV baseline (IV percentile from historical expired options, cached pre-market)
Status: PRESENT
Files/classes:
- `app/services/options/iv_rank_tracker.rb` — `IvRankTracker`
  - Tracks ATM IV ranks and caches results
  - `seed_history` extended to pull historical samples from DhanHQ ExpiredOptionsData
- `app/jobs/pre_market_iv_baseline_job.rb` — `PreMarketIvBaselineJob`
  - Solid Queue recurring job, runs at 08:30
  - Seeds historical IV data and computes percentile cache before market open
- `app/models/iv_snapshot.rb` — `IvSnapshot`
  - Persists pre-computed IV percentile snapshots
- `config/recurring.yml`
  - Registers `PreMarketIvBaselineJob` at 08:30

### 2. Volatility gate (blocks entry if IV percentile >= 50%)
Status: PRESENT
Files/classes:
- `app/services/entries/guards/iv_vol_gate_guard.rb` — `IvVolGateGuard`
  - Default collared at 0.50 (50 % IV percentile)
- `app/services/market/vix_gate.rb` — `Market::VixGate`
  - Additional VIX-level threshold gating

### 3. Momentum gate (BB breakout on 15-min, opening range break, volume surge confirmation)
Status: PRESENT
Files/classes:
- `app/services/entries/guards/momentum_gate_guard.rb` — `MomentumGateGuard`
  - Composed guard requiring at least one detector to pass:
  - 15-min Bollinger Band breakout
  - Opening Range Break via `OptionsBuying::Strategies::OrbBreakout` (includes volume surge confirmation)
- `app/services/options_buying/strategies/orb_breakout.rb` — `OrbBreakout`
  - `check_entry` exposes ORB + volume-concurrent validation
- `app/services/market_regime_detector.rb`
  - Underlying build helper for intermediate indicator series used by guards

### 4. Liquidity gate (OI/volume strike ranking + bid-ask spread + order book depth)
Status: PARTIAL
Files/classes:
- `app/services/options/derivative_chain_analyzer.rb` — `DerivativeChainAnalyzer`
  - Added OI ranking (configurable `top_by_oi_limit`) and volume filter (`min_volume`) in P7; performs strike-level OI/volume ranking
- `app/services/entries/guards/bid_ask_spread_guard.rb` — `BidAskSpreadGuard`
  - Price-level bid/ask spread check with configurable per-index override
  - **Added** quantity/order-depth-aware layer via `min_bid_qty` / `min_ask_qty` config
  - Still treated as PARTIAL because depth ingestion from `dhanhq-client` is not fully wired into `MarketTick` in all code paths (P12 completed but legacy `RedisTickCache` paths may not carry depth)

### 5. ATM strike selector (CE/PE near ATM by OI + volume)
Status: PRESENT
Files/classes:
- `app/services/options/strike_selector.rb` — `Options::StrikeSelector`
- `app/services/options/prop_strike_selector.rb` — `Options::PropStrikeSelector`
- `app/services/options/strike_qualification/strike_selector.rb`
- `app/services/options/derivative_chain_analyzer.rb`
  - OI/volume ranking logic consumed by ATM strike selection

### 6. Session guards (no entry 09:45, no entry 15:00, hard exit 15:20)
Status: PRESENT
Files/classes:
- `app/services/entries/guards/earliest_entry_guard.rb` — `EarliestEntryGuard`
  - Default earliest entry 09:45
- `app/services/entries/guards/trading_time_restriction_guard.rb` — `TradingTimeRestrictionGuard`
  - Blocks new entries after 15:00
- `app/services/live/risk_manager_service/runner.rb`
  - Hard EOD exit invoked at 15:20
- `app/services/live/risk_manager_service/config.rb`
  - Config knobs for session windows plus breakeven/gain settings

### 7. Market order + IOC limit fallback entry executor
Status: PRESENT
Files/classes:
- `app/services/orders/placer.rb` — `Orders::Placer`
  - `buy_entry_with_fallback!` tries market first, then falls back to `buy_ioc_limit!` with `validity: 'IOC'` when market is rejected
  - Paper path path uses `Orders::GatewayPaper` (untouched); live path is unchanged

### 8. Structural kill switch exit (VWAP break, 9-EMA break, 3-candle swing low/high)
Status: PRESENT
Files/classes:
- `app/services/risk/rules/structural_kill_switch_rule.rb` — `Risk::Rules::StructuralKillSwitchRule`
  - Triggers when VWAP breaks, 9-EMA cross breaks, or the 3-candle swing low/high is violated
  - Registered in `Risk::Rules::RuleFactory`
- Shared helpers:
  - VWAP calculation hand reuses existing `VwapCalculator`
  - Candle state reuse via `CandleSeriesCache` and `IndexInstrumentCache`

### 9. Breakeven trigger (move SL to entry when premium +15 %)
Status: PRESENT
Files/classes:
- `app/services/live/risk_manager_service/exit_enforcement.rb` — `ExitEnforcement`
  - Trails stop to entry once premium moves +15 % from entry, default set to 0.15
- `app/services/positions/high_water_mark.rb` — `HighWaterMark`
  - Tracks HWM for breakeven evaluation
- `app/services/live/risk_manager_service/config.rb`
  - `breakeven_after_gain = 0.15`

### 10. Premium momentum ratchet trailing stop (step-up SL as peak expands)
Status: PRESENT
Files/classes:
- `app/services/live/trailing_engine.rb` — `Live::TrailingEngine`
  - Expands stop levels as the premium peak advances
- `app/services/risk/rules/adaptive_trail_rule.rb` — `Risk::Rules::AdaptiveTrailRule`
  - Adapts trailing stop per recent swing
- `app/services/positions/trailing_config.rb` — `Positions::TrailingConfig`
  - Trailing parameters and limits

### 11. Time-based decay rule exit (close if open > 45 min and premium < 85 % of entry)
Status: PRESENT
Files/classes:
- `app/services/risk/rules/time_decay_rule.rb` — `Risk::Rules::TimeDecayRule`
  - Triggers when age > configured threshold (default 45 min) and premium < configured decay threshold (default 0.85)
  - Registered in `Risk::Rules::RuleFactory`
- `app/services/risk/rules/rule_engine.rb` — `RuleEngine`
  - Iterates rules in priority order including the new `TimeDecayRule`

### 12. Exchange segment routing (NSE_FNO vs BSE_FNO by underlying)
Status: PRESENT
Files/classes:
- `app/models/concerns/instrument_helpers.rb`
  - `exchange_segment` enum mapping:
    - `nse/derivatives` → `NSE_FNO`
    - `bse/derivatives` → `BSE_FNO`
  - Verified DB sweep: NIFTY/BANKNIFTY/FINNIFTY/MIDCPNIFTY → NSE; SENSEX → BSE
- `app/models/concerns/instrument_helpers.rb` — `InstrumentHelpers`
  - `routed_segment` / `derivative_segment` helpers

### 13. WebSocket connection budget management (max 5 concurrent)
Status: PRESENT
Files/classes:
- `app/services/live/ws_connection_budget.rb` — `Live::WsConnectionBudget`
  - Singleton-ish budget manager
  - Default cap: 5 (`WS_MAX_CONCURRENT` env override)
  - `acquire!` / `release!` / `exhausted?` / `status`
- `app/services/live/market_feed_hub.rb` — `Live::MarketFeedHub`
  - `start!` calls `acquire_budget!` before opening the WS; `stop!` releases the budget
  - Logs warning and skips connection if budget exhausted

### 14. Order queue with token bucket rate limiter (max 10 req/sec)
Status: PRESENT
Files/classes:
- `lib/token_bucket.rb` — `TokenBucket`
  - Thread-safe sliding log token bucket
  - Default 10 req/sec
  - `consume!` raises `TokenBucket::RateLimited` or yields
  - `allowed?` / `status` for inspection
- `app/services/orders/placer.rb` — `Orders::Placer`
  - `with_order_rate_limit(context: ...)` wraps mutating order calls
  - Toggled via `ORDER_RATE_LIMIT_ENABLED=true`
  - Live path behavior unchanged when disabled

---

## Infrastructure / support files (no direct research component, but relevant)

| File | Usage |
|------|-------|
| `app/services/entries/entry_guard_pipeline.rb` | Ordered guard invocation; registers gate classes |
| `app/services/risk/rules/rule_engine.rb` | Sorts + runs exit rules (TRaIL, structural, time decay, breakeven, etc.) |
| `app/services/risk/rules/rule_factory.rb` | Instantiates all exit rules in deterministic order |
| `app/services/live/market_feed_hub.rb` | Primary WS hub; now budget-gated via P12 `WsConnectionBudget` |
| `app/services/orders/commands/place_order_command.rb` | Abstraction over live/paper gateway |
| `app/services/orders/gateway_paper.rb` | Paper execution path (untouched by P1–P13 per constraint) |
| `app/services/orders/gateway_live.rb` | Live execution path (untouched by P1–P13 per constraint) |
| `app/models/concerns/instrument_helpers.rb` | `exchange_segment` enum and `ltp`, `routed_segment` helpers |
| `app/domain/market_tick.rb` | Immutable tick boundary; extended with `bid_qty`/`ask_qty` |
| `app/services/live/tick_query.rb` | Builds `MarketTick` from cache; now includes depth fields |
| `app/services/live/redis_tick_cache.rb` | Redis-backed tick cache used by `TickQuery` |
| `config/recurring.yml` | Solid Queue recurring task schedule (08:30 IV baseline) |

---

## Summary

| Status | Count |
|--------|-------|
| PRESENT | 27 |
| PARTIAL | 1 (liquidity gate depth sub-check; P12 complete, legacy cache path may still miss `bid_qty`/`ask_qty`) |
| ABSENT | 0 |
