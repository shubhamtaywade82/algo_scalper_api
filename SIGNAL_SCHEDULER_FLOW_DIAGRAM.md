# Signal Scheduler - Visual Flow Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Signal::Scheduler                         │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  Main Thread Loop (30s cycles)                        │ │
│  │  ┌─────────────────────────────────────────────────┐ │ │
│  │  │  For each index in config                        │ │ │
│  │  │  ┌─────────────────────────────────────────────┐ │ │ │
│  │  │  │  process_index(index_cfg)                   │ │ │ │
│  │  │  │  ┌───────────────────────────────────────┐ │ │ │ │
│  │  │  │  │  evaluate_supertrend_signal()         │ │ │ │ │
│  │  │  │  │  ┌─────────────────────────────────┐ │ │ │ │ │
│  │  │  │  │  │  Path Selection                  │ │ │ │ │ │
│  │  │  │  │  └─────────────────────────────────┘ │ │ │ │ │
│  │  │  │  │         │                             │ │ │ │ │
│  │  │  │  │    ┌────┴────┐                        │ │ │ │ │
│  │  │  │  │    │         │                        │ │ │ │ │
│  │  │  │  │  Path 1    Path 2                     │ │ │ │ │
│  │  │  │  │  Trend     Legacy                     │ │ │ │ │
│  │  │  │  │  Scorer    Indicators                 │ │ │ │ │
│  │  │  │  │    │         │                        │ │ │ │ │
│  │  │  │  │    └────┬────┘                        │ │ │ │ │
│  │  │  │  │         │                             │ │ │ │ │
│  │  │  │  │  select_candidate_from_chain()       │ │ │ │ │
│  │  │  │  │         │                             │ │ │ │ │
│  │  │  │  │  process_signal()                    │ │ │ │ │
│  │  │  │  │         │                             │ │ │ │ │
│  │  │  │  │  Entries::EntryGuard.try_enter()     │ │ │ │ │
│  │  │  │  └───────────────────────────────────────┘ │ │ │ │
│  │  │  └─────────────────────────────────────────────┘ │ │ │
│  │  │  Sleep 5s (between indices)                      │ │ │
│  │  └─────────────────────────────────────────────────┘ │ │
│  │  Sleep 30s (between cycles)                          │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Path 1: Trend Scorer Flow

```
evaluate_with_trend_scorer()
  │
  ├─→ Signal::TrendScorer.compute_direction()
  │     │
  │     ├─→ Get Instrument (IndexInstrumentCache)
  │     │
  │     ├─→ Get Primary Series (1m)
  │     │     └─→ instrument.candle_series(interval: '1')
  │     │
  │     ├─→ Get Confirmation Series (5m)
  │     │     └─→ instrument.candle_series(interval: '5')
  │     │
  │     ├─→ Calculate PA Score (0-7)
  │     │     ├─→ Momentum check
  │     │     ├─→ Structure breaks
  │     │     ├─→ Candle patterns
  │     │     └─→ Trend consistency
  │     │
  │     ├─→ Calculate IND Score (0-7)
  │     │     ├─→ RSI(14) → Indicators::Calculator.rsi()
  │     │     ├─→ MACD(12,26,9) → Indicators::Calculator.macd()
  │     │     ├─→ ADX(14) → Indicators::Calculator.adx()
  │     │     └─→ Supertrend → Indicators::Supertrend.new().call()
  │     │
  │     ├─→ Calculate MTF Score (0-7)
  │     │     ├─→ RSI alignment (primary vs confirmation)
  │     │     ├─→ Trend alignment (Supertrend)
  │     │     └─→ Price alignment
  │     │
  │     └─→ Determine Direction
  │           ├─→ trend_score >= 14.0 → :bullish
  │           ├─→ trend_score <= 7.0 → :bearish
  │           └─→ Otherwise → nil (no signal)
  │
  └─→ If direction confirmed:
        └─→ select_candidate_from_chain()
```

## Path 2: Legacy Indicators Flow

```
evaluate_with_legacy_indicators()
  │
  ├─→ Signal::Engine.analyze_multi_timeframe()
  │     │
  │     ├─→ Primary Timeframe Analysis ('5m')
  │     │     ├─→ instrument.candle_series(interval: '5')
  │     │     ├─→ Indicators::Supertrend.new(series, **cfg).call()
  │     │     ├─→ instrument.adx(14, interval: '5')
  │     │     └─→ decide_direction(supertrend, adx, min_strength)
  │     │
  │     ├─→ Confirmation Timeframe Analysis ('15m') [if enabled]
  │     │     ├─→ instrument.candle_series(interval: '15')
  │     │     ├─→ Indicators::Supertrend.new(series, **cfg).call()
  │     │     ├─→ instrument.adx(14, interval: '15')
  │     │     └─→ decide_direction(supertrend, adx, min_strength)
  │     │
  │     └─→ multi_timeframe_direction(primary, confirmation)
  │           ├─→ Both :bullish → :bullish
  │           ├─→ Both :bearish → :bearish
  │           ├─→ Either :avoid → :avoid
  │           └─→ Mismatch → :avoid
  │
  └─→ If direction confirmed:
        └─→ select_candidate_from_chain()
```

## Chain Analysis Flow

```
select_candidate_from_chain()
  │
  ├─→ Options::ChainAnalyzer.new(...)
  │     │
  │     ├─→ Get Expiry List
  │     │     └─→ instrument.expiry_list
  │     │
  │     ├─→ Find Next Expiry
  │     │     └─→ find_next_expiry(expiry_list)
  │     │
  │     ├─→ Fetch Option Chain
  │     │     └─→ instrument.fetch_option_chain(expiry_date)
  │     │
  │     ├─→ Filter Strikes
  │     │     ├─→ Calculate ATM strike
  │     │     ├─→ Select target strikes (ATM, ATM±1, ATM±2, ATM±3)
  │     │     ├─→ Filter by IV range
  │     │     ├─→ Filter by OI (min_oi)
  │     │     ├─→ Filter by spread (max_spread_pct)
  │     │     └─→ Filter by delta (min_delta)
  │     │
  │     ├─→ Score Strikes
  │     │     ├─→ ATM Preference Score (0-100)
  │     │     ├─→ Liquidity Score (0-50)
  │     │     ├─→ Delta Score (0-30)
  │     │     ├─→ IV Score (0-20)
  │     │     └─→ Price Efficiency Score (0-10)
  │     │
  │     └─→ Return Top Candidates (sorted by score)
  │
  └─→ Return first candidate
```

## Entry Execution Flow

```
Entries::EntryGuard.try_enter()
  │
  ├─→ [Validation Phase]
  │     ├─→ Find Instrument
  │     ├─→ TradingSession::Service.entry_allowed?()
  │     ├─→ Live::DailyLimits.can_trade?()
  │     ├─→ exposure_ok?()
  │     └─→ cooldown_active?()
  │
  ├─→ [LTP Resolution Phase]
  │     ├─→ Try WebSocket TickCache
  │     │     └─→ Live::TickCache.ltp(segment, security_id)
  │     │
  │     ├─→ If not available, subscribe to WebSocket
  │     │     └─→ Live::MarketFeedHub.instance.subscribe(...)
  │     │
  │     ├─→ Poll for tick (up to 300ms, 6 attempts)
  │     │
  │     └─→ Fallback to REST API
  │           └─→ DhanHQ::Models::MarketFeed.ltp(...)
  │
  ├─→ [Quantity Calculation Phase]
  │     └─→ Capital::Allocator.qty_for(...)
  │
  ├─→ [Order Placement Phase]
  │     ├─→ Paper Mode:
  │     │     └─→ create_paper_tracker!()
  │     │
  │     └─→ Live Mode:
  │           ├─→ Orders.config.place_market(...)
  │           └─→ create_tracker!()
  │
  └─→ [Post-Entry Setup Phase]
        ├─→ Subscribe to market feed
        ├─→ Add to ActiveCache
        └─→ Place initial bracket orders (SL/TP)
```

## Timing Diagram

```
Time →
│
├─ 0s ────────────────────────────────────────────────────────┐
│   │ Start Cycle                                              │
│   │ Check Market Status                                      │
│   │                                                           │
├─ 0s ────────────────────────────────────────────────────────┤
│   │ Process Index 1 (NIFTY)                                  │
│   │   ├─ Get Instrument                                      │
│   │   ├─ Evaluate Signal                                     │
│   │   ├─ Select Candidate                                    │
│   │   └─ Try Entry                                           │
│   │                                                           │
├─ 5s ────────────────────────────────────────────────────────┤
│   │ Process Index 2 (BANKNIFTY)                               │
│   │   ├─ Get Instrument                                      │
│   │   ├─ Evaluate Signal                                     │
│   │   ├─ Select Candidate                                    │
│   │   └─ Try Entry                                           │
│   │                                                           │
├─ 10s ───────────────────────────────────────────────────────┤
│   │ Process Index 3 (SENSEX)                                  │
│   │   ├─ Get Instrument                                      │
│   │   ├─ Evaluate Signal                                     │
│   │   ├─ Select Candidate                                    │
│   │   └─ Try Entry                                           │
│   │                                                           │
├─ 15s ───────────────────────────────────────────────────────┤
│   │ [All indices processed]                                   │
│   │                                                           │
├─ 30s ────────────────────────────────────────────────────────┤
│   │ Sleep until next cycle                                    │
│   │                                                           │
├─ 30s ────────────────────────────────────────────────────────┤
│   │ Next Cycle Starts                                         │
│   └───────────────────────────────────────────────────────────┘
```

## Service Dependencies Graph

```
Signal::Scheduler
  │
  ├─→ IndexInstrumentCache (Singleton)
  │     └─→ Instrument Model
  │
  ├─→ Signal::TrendScorer
  │     ├─→ Indicators::Calculator
  │     │     ├─→ RSI
  │     │     ├─→ MACD
  │     │     └─→ ADX
  │     └─→ Indicators::Supertrend
  │
  ├─→ Signal::Engine
  │     ├─→ Indicators::Supertrend
  │     └─→ Instrument.adx()
  │
  ├─→ Options::ChainAnalyzer
  │     ├─→ Instrument.expiry_list()
  │     ├─→ Instrument.fetch_option_chain()
  │     └─→ Derivative Model
  │
  └─→ Entries::EntryGuard
        ├─→ TradingSession::Service
        ├─→ Live::DailyLimits
        ├─→ Capital::Allocator
        ├─→ Live::MarketFeedHub (Singleton)
        ├─→ Live::TickCache (Singleton)
        ├─→ Orders.config
        ├─→ PositionTracker Model
        ├─→ Positions::ActiveCache (Singleton)
        └─→ Orders::BracketPlacer
```

## Error Handling Flow

```
┌─────────────────────────────────────────┐
│  process_index(index_cfg)                │
└─────────────────────────────────────────┘
           │
           ├─→ [Success] → process_signal()
           │
           └─→ [Error] → rescue StandardError
                          │
                          ├─→ Log Error
                          │   "[SignalScheduler] process_index error"
                          │
                          └─→ Continue to next index
```

## State Transitions

```
┌─────────────┐
│  Stopped    │
└──────┬──────┘
       │ start()
       ▼
┌─────────────┐
│  Starting   │
└──────┬──────┘
       │ Thread created
       ▼
┌─────────────┐
│  Running    │──→ [Market Closed] ──→ Sleep 30s ──┐
└──────┬──────┘                                    │
       │                                            │
       │ [Processing Indices]                       │
       │                                            │
       └────────────────────────────────────────────┘
       │
       │ stop()
       ▼
┌─────────────┐
│  Stopping   │
└──────┬──────┘
       │ Thread.join(2)
       ▼
┌─────────────┐
│  Stopped    │
└─────────────┘
```

## Quick Testing Reference

### Setup

```bash
# Add timecop to Gemfile
gem 'timecop', '~> 0.9.8', group: [:development, :test]

# Install
bundle install
```

### Test Commands

```bash
# Run all scheduler tests
bundle exec rspec spec/services/signal/scheduler*

# Run with VCR recording
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb

# Run with time manipulation
bundle exec rspec spec/services/signal/scheduler_time_spec.rb
```

### Timecop Usage

```ruby
# Freeze time
Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))

# Travel forward
Timecop.travel(30.seconds)

# Return to real time
Timecop.return
```

### VCR Usage

```ruby
# Mark test to use VCR
it 'fetches real data', :vcr do
  # VCR will record/playback API calls
end

# Record new cassette
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb
```

See `SIGNAL_SCHEDULER_DETAILED_ANALYSIS.md` for complete testing documentation.
