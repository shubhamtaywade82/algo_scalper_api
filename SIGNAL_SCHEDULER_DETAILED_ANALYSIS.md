# Signal Scheduler - Detailed Analysis

## Overview
The `Signal::Scheduler` is a background service that continuously monitors market indices, evaluates trading signals, and triggers entries when conditions are met. It runs in a separate thread and processes each configured index periodically.

## Architecture

### Initialization
```ruby
Signal::Scheduler.new(period: 30, data_provider: nil)
```
- **period**: Default 30 seconds between cycles
- **data_provider**: Optional provider (defaults to `Providers::DhanhqProvider`)

### Thread Management
- Runs in a dedicated thread named `'signal-scheduler'`
- Thread-safe with mutex protection
- Graceful shutdown with 2-second timeout

## Main Execution Flow

### 1. Startup Sequence (`start` method)

```
1. Check if already running (thread-safe)
2. Load indices from AlgoConfig.fetch[:indices]
3. Validate indices exist (exit if empty)
4. Create background thread
5. Enter main loop
```

### 2. Main Loop (runs continuously)

```ruby
loop do
  break unless @running
  
  # Check market status
  if TradingSession::Service.market_closed?
    sleep @period (30 seconds)
    next
  end
  
  # Process each index
  indices.each_with_index do |idx_cfg, idx|
    break unless @running
    
    # Re-check market status before each index
    if TradingSession::Service.market_closed?
      break
    end
    
    # Delay between indices (5 seconds)
    sleep(idx.zero? ? 0 : INTER_INDEX_DELAY)
    
    # Process this index
    process_index(idx_cfg)
  end
  
  # Sleep before next cycle
  sleep @period (30 seconds)
end
```

**Timing:**
- **Cycle Period**: 30 seconds (configurable)
- **Inter-Index Delay**: 5 seconds between processing different indices
- **Market Closed**: Sleeps 30 seconds when market is closed

## Signal Evaluation Flow

### Path 1: Trend Scorer (Direction-First) - If Enabled

```
evaluate_supertrend_signal(index_cfg)
  ↓
evaluate_with_trend_scorer(index_cfg, instrument)
  ↓
Signal::TrendScorer.compute_direction(index_cfg: index_cfg)
  ↓
[Trend Scoring Process]
  ↓
select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_score)
  ↓
Options::ChainAnalyzer.select_candidates()
  ↓
process_signal(index_cfg, signal)
```

**Trend Scorer Process:**
1. **Get Instrument**: `IndexInstrumentCache.instance.get_or_fetch(index_cfg)`
2. **Compute Trend Score**: Calculates composite score (0-21) from:
   - **PA_score (0-7)**: Price action patterns, structure breaks, momentum
   - **IND_score (0-7)**: Technical indicators (RSI, MACD, ADX, Supertrend)
   - **MTF_score (0-7)**: Multi-timeframe alignment
3. **Direction Decision**:
   - Score >= 14.0 → `:bullish`
   - Score <= 7.0 → `:bearish`
   - Otherwise → `nil` (no signal)
4. **Chain Analysis**: If direction confirmed, select option candidate

### Path 2: Legacy Supertrend + ADX (Default)

```
evaluate_supertrend_signal(index_cfg)
  ↓
evaluate_with_legacy_indicators(index_cfg, instrument)
  ↓
Signal::Engine.analyze_multi_timeframe(index_cfg: index_cfg, instrument: instrument)
  ↓
[Multi-Timeframe Analysis]
  ↓
select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_metric)
  ↓
Options::ChainAnalyzer.select_candidates()
  ↓
process_signal(index_cfg, signal)
```

**Legacy Indicator Process:**
1. **Get Instrument**: `IndexInstrumentCache.instance.get_or_fetch(index_cfg)`
2. **Primary Timeframe Analysis**:
   - Fetch candle series: `instrument.candle_series(interval: '5m')`
   - Calculate Supertrend: `Indicators::Supertrend.new(series: series, **supertrend_cfg).call`
   - Calculate ADX: `instrument.adx(14, interval: interval)`
   - Determine direction: `decide_direction(supertrend_result, adx_value, min_strength)`
3. **Confirmation Timeframe Analysis** (if enabled):
   - Same process on confirmation timeframe (e.g., '15m')
   - Multi-timeframe direction: `multi_timeframe_direction(primary, confirmation)`
4. **Chain Analysis**: If direction confirmed, select option candidate

## Detailed Service Calls

### 1. IndexInstrumentCache
**Called**: `IndexInstrumentCache.instance.get_or_fetch(index_cfg)`
**Purpose**: Get or fetch instrument for the index
**When**: At the start of each index evaluation
**Returns**: `Instrument` object or `nil`

### 2. Signal::TrendScorer (Path 1)
**Called**: `Signal::TrendScorer.compute_direction(index_cfg: index_cfg)`
**Purpose**: Calculate composite trend score and determine direction
**When**: If `trend_scorer_enabled?` returns true
**Process**:
- Gets primary and confirmation timeframe series
- Calculates PA score (price action)
- Calculates IND score (indicators: RSI, MACD, ADX, Supertrend)
- Calculates MTF score (multi-timeframe alignment)
- Returns direction based on score thresholds

**Sub-calls**:
- `instrument.candle_series(interval: '1m')` - Primary timeframe
- `instrument.candle_series(interval: '5m')` - Confirmation timeframe
- `Indicators::Calculator.new(series).rsi(14)`
- `Indicators::Calculator.new(series).macd(12, 26, 9)`
- `Indicators::Calculator.new(series).adx(14)`
- `Indicators::Supertrend.new(series: series, period: 10, base_multiplier: 2.0).call`

### 3. Signal::Engine (Path 2)
**Called**: `Signal::Engine.analyze_multi_timeframe(index_cfg: index_cfg, instrument: instrument)`
**Purpose**: Analyze multiple timeframes using Supertrend + ADX
**When**: If Trend Scorer is disabled (default path)
**Process**:
- Analyzes primary timeframe (default: '5m')
- Analyzes confirmation timeframe (if enabled, e.g., '15m')
- Combines results using `multi_timeframe_direction()`

**Sub-calls**:
- `instrument.candle_series(interval: '5m')` - Primary
- `instrument.candle_series(interval: '15m')` - Confirmation (if enabled)
- `Indicators::Supertrend.new(series: series, **supertrend_cfg).call`
- `instrument.adx(14, interval: interval)`
- `decide_direction(supertrend_result, adx_value, min_strength)`

### 4. Options::ChainAnalyzer
**Called**: `Options::ChainAnalyzer.select_candidates(limit: limit, direction: direction)`
**Purpose**: Select best option strikes for the given direction
**When**: After direction is confirmed (both paths)
**Process**:
1. **Get Expiry**: `instrument.expiry_list` → Find next expiry
2. **Fetch Chain**: `instrument.fetch_option_chain(expiry_date)`
3. **Filter Strikes**:
   - Calculate ATM strike
   - Select target strikes (ATM, ATM±1, ATM±2, ATM±3)
   - Filter by IV range, OI, spread, delta
4. **Score Strikes**: Calculate score based on:
   - ATM preference (0-100)
   - Liquidity (OI + spread) (0-50)
   - Delta (0-30)
   - IV (0-20)
   - Price efficiency (0-10)
5. **Return Top Candidates**: Sorted by score

**Sub-calls**:
- `instrument.expiry_list`
- `instrument.fetch_option_chain(expiry_date)`
- `Derivative.find_by(...)` - Find derivative records
- `AlgoConfig.fetch[:option_chain]` - Get filter criteria

### 5. Entries::EntryGuard
**Called**: `Entries::EntryGuard.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, scale_multiplier: multiplier)`
**Purpose**: Validate and execute entry order
**When**: After signal is generated and candidate selected
**Process**:
1. **Validation Checks**:
   - Find instrument
   - Check trading session timing (`TradingSession::Service.entry_allowed?`)
   - Check daily limits (`Live::DailyLimits.can_trade?`)
   - Check exposure limits (`exposure_ok?`)
   - Check cooldown (`cooldown_active?`)
2. **LTP Resolution**:
   - Try WebSocket TickCache first
   - Fallback to REST API if needed
   - Subscribe to market feed if not already subscribed
3. **Quantity Calculation**:
   - `Capital::Allocator.qty_for(...)` - Calculate position size
   - Handle paper trading fallback if insufficient balance
4. **Order Placement**:
   - **Paper Mode**: Create `PositionTracker` directly
   - **Live Mode**: `Orders.config.place_market(...)` → Create tracker
5. **Post-Entry Setup**:
   - Subscribe to market feed
   - Add to ActiveCache
   - Place initial bracket orders (SL/TP)

**Sub-calls**:
- `TradingSession::Service.entry_allowed?`
- `Live::DailyLimits.new.can_trade?`
- `Capital::Allocator.qty_for(...)`
- `Live::MarketFeedHub.instance.subscribe(...)`
- `Live::TickCache.ltp(segment, security_id)`
- `DhanHQ::Models::MarketFeed.ltp(...)` - API fallback
- `Orders.config.place_market(...)` - Live orders
- `Positions::ActiveCache.instance.add_position(...)`
- `Orders::BracketPlacer.place_bracket(...)`

## Complete Call Chain (Example)

### Scenario: Bullish Signal Detected for NIFTY

```
[Thread: signal-scheduler]
  ↓
Main Loop (every 30 seconds)
  ↓
process_index({key: 'NIFTY', ...})
  ↓
evaluate_supertrend_signal({key: 'NIFTY', ...})
  ↓
IndexInstrumentCache.instance.get_or_fetch({key: 'NIFTY'})
  ↓
[Path Selection]
  ├─→ Trend Scorer Path (if enabled)
  │     ↓
  │     Signal::TrendScorer.compute_direction(...)
  │     ↓
  │     [Get Series]
  │     instrument.candle_series(interval: '1m')
  │     instrument.candle_series(interval: '5m')
  │     ↓
  │     [Calculate Scores]
  │     pa_score(primary_series) → 5.2
  │     ind_score(primary_series) → 6.1
  │     mtf_score(primary_series, confirmation_series) → 4.8
  │     ↓
  │     trend_score = 16.1 → :bullish
  │
  └─→ Legacy Path (default)
        ↓
        Signal::Engine.analyze_multi_timeframe(...)
        ↓
        [Primary Timeframe]
        instrument.candle_series(interval: '5m')
        Indicators::Supertrend.new(...).call → {trend: :bullish, ...}
        instrument.adx(14, interval: '5m') → 28.5
        decide_direction(...) → :bullish
        ↓
        [Confirmation Timeframe] (if enabled)
        instrument.candle_series(interval: '15m')
        Indicators::Supertrend.new(...).call → {trend: :bullish, ...}
        instrument.adx(14, interval: '15m') → 25.2
        decide_direction(...) → :bullish
        ↓
        multi_timeframe_direction(:bullish, :bullish) → :bullish
  ↓
select_candidate_from_chain({key: 'NIFTY'}, :bullish, chain_cfg, trend_score)
  ↓
Options::ChainAnalyzer.new(...).select_candidates(limit: 3, direction: :bullish)
  ↓
[Chain Analysis]
  instrument.expiry_list → ['2024-01-25', '2024-02-01', ...]
  find_next_expiry(...) → '2024-01-25'
  instrument.fetch_option_chain('2024-01-25')
  ↓
  [Filter & Score]
  Calculate ATM strike: 24500
  Target strikes: [24500, 24550, 24600] (CE)
  Filter by IV, OI, spread, delta
  Score each strike
  ↓
  Return: [{segment: 'NSE_FNO', security_id: '12345', symbol: 'NIFTY-25Jan2024-24500-CE', ...}, ...]
  ↓
process_signal({key: 'NIFTY'}, signal)
  ↓
build_pick_from_signal(signal)
  ↓
Entries::EntryGuard.try_enter(...)
  ↓
[Entry Validation]
  TradingSession::Service.entry_allowed? → {allowed: true}
  Live::DailyLimits.can_trade? → {allowed: true}
  exposure_ok? → true
  cooldown_active? → false
  ↓
[LTP Resolution]
  Live::MarketFeedHub.instance.subscribe(segment: 'NSE_FNO', security_id: '12345')
  Live::TickCache.ltp('NSE_FNO', '12345') → 245.50
  ↓
[Quantity Calculation]
  Capital::Allocator.qty_for(...) → 1 lot
  ↓
[Order Placement]
  Orders.config.place_market(...) → {order_id: 'ORD123456'}
  ↓
[Create Tracker]
  PositionTracker.build_or_average!(...)
  ↓
[Post-Entry Setup]
  Live::MarketFeedHub.instance.subscribe_instrument(...)
  Positions::ActiveCache.instance.add_position(...)
  Orders::BracketPlacer.place_bracket(...)
  ↓
✅ Entry Successful
```

## Timing and Loops

### Outer Loop (Main Cycle)
- **Frequency**: Every 30 seconds (configurable)
- **Condition**: Continues while `@running == true`
- **Market Check**: Skips processing if market closed

### Inner Loop (Index Processing)
- **Frequency**: Processes each index sequentially
- **Delay**: 5 seconds between indices (`INTER_INDEX_DELAY`)
- **Condition**: Breaks if market closes during processing

### Service-Specific Loops

#### Trend Scorer
- **No loops**: Single calculation per call
- **Time Complexity**: O(n) where n = number of candles

#### Chain Analyzer
- **Loop**: Iterates through all strikes in option chain
- **Filtering**: Multiple passes (IV, OI, spread, delta)
- **Scoring**: One pass to calculate scores
- **Time Complexity**: O(m) where m = number of strikes

#### Entry Guard
- **No loops**: Single entry attempt per call
- **Polling**: WebSocket LTP resolution polls up to 300ms (6 attempts × 50ms)

## Error Handling

### Per-Index Errors
```ruby
rescue StandardError => e
  Rails.logger.error("[SignalScheduler] process_index error #{index_cfg[:key]}: #{e.class} - #{e.message}")
  # Continues to next index
end
```

### Cycle-Level Errors
```ruby
rescue StandardError => e
  Rails.logger.error("[SignalScheduler] Cycle error: #{e.class} - #{e.message}")
  # Continues to next cycle
end
```

### Service-Level Errors
Each service (TrendScorer, Engine, ChainAnalyzer, EntryGuard) has its own error handling:
- Returns `nil` or empty array on error
- Logs errors with context
- Allows scheduler to continue processing other indices

## Configuration Dependencies

### Required Config (`AlgoConfig.fetch`)
- `[:indices]` - Array of index configurations
- `[:signals]` - Signal configuration
  - `[:primary_timeframe]` - Default '5m'
  - `[:confirmation_timeframe]` - Optional (e.g., '15m')
  - `[:supertrend]` - Supertrend parameters
  - `[:adx]` - ADX thresholds
- `[:chain_analyzer]` - Option chain analysis config
- `[:risk]` - Risk management config
- `[:feature_flags]` - Feature toggles
  - `[:enable_trend_scorer]` - Enable Trend Scorer path
  - `[:enable_direction_before_chain]` - Legacy flag

### Index Configuration Structure
```ruby
{
  key: 'NIFTY',           # Index symbol
  sid: '13',              # Security ID
  segment: 'IDX_I',       # Segment code
  direction: :bullish,    # Optional override
  adx_thresholds: {       # Optional per-index ADX thresholds
    primary_min_strength: 20,
    confirmation_min_strength: 25
  },
  max_same_side: 2,       # Max positions per direction
  cooldown_sec: 300       # Cooldown between entries
}
```

## Performance Considerations

### Caching
- **IndexInstrumentCache**: Caches instrument lookups
- **TickCache**: In-memory cache for LTP data
- **RedisPnlCache**: Redis cache for PnL calculations

### Optimization
- **Early Exits**: Skips processing when market closed
- **Batch Operations**: Chain analyzer processes strikes in batch
- **Lazy Loading**: Instrument data loaded only when needed

### Resource Usage
- **Thread**: Single background thread
- **Memory**: Minimal (caches are shared singletons)
- **CPU**: Moderate (indicator calculations are CPU-intensive)
- **Network**: API calls only when needed (cached when possible)

## Monitoring Points

### Key Metrics to Monitor
1. **Cycle Time**: Time taken per cycle
2. **Index Processing Time**: Time per index
3. **Signal Generation Rate**: Signals per hour
4. **Entry Success Rate**: Successful entries / total signals
5. **Error Rate**: Errors per cycle

### Log Patterns
- `[SignalScheduler]` - Main scheduler logs
- `[Signal]` - Signal engine logs
- `[TrendScorer]` - Trend scorer logs
- `[Options]` - Chain analyzer logs
- `[EntryGuard]` - Entry guard logs

## Summary

The Signal Scheduler is a sophisticated background service that:
1. **Runs continuously** in a background thread (30-second cycles)
2. **Processes each index** sequentially with delays
3. **Evaluates signals** using either Trend Scorer or Legacy indicators
4. **Selects option candidates** using sophisticated scoring
5. **Executes entries** through EntryGuard with comprehensive validation
6. **Handles errors gracefully** to ensure continuous operation

The system is designed for reliability, with multiple fallbacks, comprehensive error handling, and efficient caching to minimize API calls and database queries.
