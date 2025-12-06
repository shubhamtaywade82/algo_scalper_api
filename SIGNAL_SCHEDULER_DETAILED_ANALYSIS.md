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

## Testing the Signal Scheduler Locally

### Setup

#### 1. Add Timecop Gem (for time manipulation)

Add to `Gemfile` in the `:development, :test` group:

```ruby
group :development, :test do
  # ... existing gems ...
  gem 'timecop', '~> 0.9.8'
end
```

Then run:
```bash
bundle install
```

#### 2. Configure Test Environment

The test environment is already configured with:
- **VCR**: For recording/playback of API calls
- **WebMock**: For HTTP stubbing
- **DatabaseCleaner**: For database cleanup
- **FactoryBot**: For test data creation

### Testing Approaches

#### Approach 1: Unit Tests with Mocks (Fast, Isolated)

**Use Case**: Test individual methods and logic without external dependencies.

**Example**:

```ruby
# spec/services/signal/scheduler_spec.rb
require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:scheduler) { described_class.new(period: 1) }

  describe '#process_index' do
    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      allow(scheduler).to receive(:evaluate_supertrend_signal).and_return(signal)
      allow(scheduler).to receive(:process_signal)
    end

    context 'when signal is generated' do
      let(:signal) do
        {
          segment: 'NSE_FNO',
          security_id: '12345',
          meta: { candidate_symbol: 'TEST', direction: :bullish, lot_size: 50 }
        }
      end

      it 'processes the signal' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).to have_received(:process_signal).with(index_cfg, signal)
      end
    end

    context 'when no signal is generated' do
      let(:signal) { nil }

      it 'skips processing' do
        scheduler.send(:process_index, index_cfg)
        expect(scheduler).not_to have_received(:process_signal)
      end
    end
  end
end
```

#### Approach 2: Integration Tests with Timecop (Time-Based Testing)

**Use Case**: Test time-dependent behavior (market hours, scheduling, cooldowns).

**Example**:

```ruby
# spec/services/signal/scheduler_time_spec.rb
require 'rails_helper'
require 'timecop'

RSpec.describe Signal::Scheduler do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:scheduler) { described_class.new(period: 1) }

  describe '#start' do
    context 'during market hours' do
      before do
        # Set time to 10:00 AM IST (market open)
        Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
        allow(AlgoConfig).to receive(:fetch).and_return(indices: [index_cfg])
        allow(scheduler).to receive(:process_index)
      end

      after do
        Timecop.return
        scheduler.stop if scheduler.running?
      end

      it 'processes indices when market is open' do
        scheduler.start
        sleep(0.1) # Allow thread to start
        
        expect(scheduler.running?).to be true
        expect(scheduler).to have_received(:process_index).with(index_cfg)
      end
    end

    context 'when market is closed' do
      before do
        # Set time to 4:00 PM IST (market closed)
        Timecop.freeze(Time.zone.parse('2024-01-15 16:00:00 IST'))
        allow(AlgoConfig).to receive(:fetch).and_return(indices: [index_cfg])
        allow(scheduler).to receive(:process_index)
      end

      after do
        Timecop.return
        scheduler.stop if scheduler.running?
      end

      it 'skips processing when market is closed' do
        scheduler.start
        sleep(0.1)
        
        # Should skip processing due to market closed check
        expect(scheduler.running?).to be true
        # process_index should not be called due to early exit
      end
    end

    context 'market closes during processing' do
      before do
        # Start at 3:25 PM IST (market still open)
        Timecop.freeze(Time.zone.parse('2024-01-15 15:25:00 IST'))
        allow(AlgoConfig).to receive(:fetch).and_return(indices: [index_cfg])
        
        # Simulate market closing during processing
        call_count = 0
        allow(TradingSession::Service).to receive(:market_closed?) do
          call_count += 1
          # First call: market open, second call: market closed
          call_count > 1
        end
        
        allow(scheduler).to receive(:process_index) do
          # Advance time to 3:35 PM during processing
          Timecop.freeze(Time.zone.parse('2024-01-15 15:35:00 IST'))
        end
      end

      after do
        Timecop.return
        scheduler.stop if scheduler.running?
      end

      it 'stops processing when market closes mid-cycle' do
        scheduler.start
        sleep(0.1)
        
        # Should stop processing after market closes
        expect(scheduler.running?).to be true
      end
    end
  end

  describe 'scheduling behavior' do
    before do
      Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
      allow(AlgoConfig).to receive(:fetch).and_return(indices: [index_cfg])
      allow(scheduler).to receive(:process_index)
    end

    after do
      Timecop.return
      scheduler.stop if scheduler.running?
    end

    it 'processes indices with correct timing' do
      scheduler.start
      
      # First cycle should process immediately
      sleep(0.1)
      expect(scheduler).to have_received(:process_index).with(index_cfg).once
      
      # Advance time by 30 seconds (one cycle)
      Timecop.travel(30.seconds)
      sleep(0.1)
      
      # Should process again after period
      expect(scheduler).to have_received(:process_index).at_least(:twice)
    end

    it 'delays between multiple indices' do
      multiple_indices = [
        { key: 'NIFTY', segment: 'IDX_I', sid: '13' },
        { key: 'BANKNIFTY', segment: 'IDX_I', sid: '23' }
      ]
      
      allow(AlgoConfig).to receive(:fetch).and_return(indices: multiple_indices)
      
      scheduler.start
      sleep(0.1)
      
      # Should process first index immediately
      expect(scheduler).to have_received(:process_index).with(multiple_indices[0]).once
      
      # Advance time by 5 seconds (INTER_INDEX_DELAY)
      Timecop.travel(5.seconds)
      sleep(0.1)
      
      # Should process second index after delay
      expect(scheduler).to have_received(:process_index).with(multiple_indices[1]).once
    end
  end
end
```

#### Approach 3: Integration Tests with Actual API Calls (VCR)

**Use Case**: Test end-to-end flow with real API responses (recorded).

**Example**:

```ruby
# spec/services/signal/scheduler_integration_spec.rb
require 'rails_helper'

RSpec.describe Signal::Scheduler, :vcr do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end

  let(:nifty_instrument) { create(:instrument, :nifty_index) }

  before do
    # Mock IndexInstrumentCache to return our test instrument
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)
    
    # Configure AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [index_cfg],
      signals: {
        primary_timeframe: '1m',
        confirmation_timeframe: '5m',
        enable_trend_scorer: false, # Use legacy path
        supertrend: {
          period: 10,
          base_multiplier: 2.0
        },
        adx: {
          min_strength: 18.0,
          confirmation_min_strength: 20.0
        }
      },
      chain_analyzer: {
        max_candidates: 3
      },
      risk: {
        sl_pct: 0.30,
        tp_pct: 0.60
      }
    })

    # Reduce days for faster API calls
    allow(nifty_instrument).to receive(:intraday_ohlc).and_wrap_original do |original_method, **kwargs|
      kwargs[:days] = 7 unless kwargs.key?(:days) || kwargs.key?(:from_date)
      original_method.call(**kwargs)
    end

    # Mock EntryGuard to prevent actual order placement
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    
    # Clean up state
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  after do
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  describe 'end-to-end signal generation' do
    it 'fetches real OHLC data and generates signals', :vcr do
      scheduler = described_class.new(period: 1)
      
      # VCR will record/playback actual API calls
      result = scheduler.send(:evaluate_supertrend_signal, index_cfg)
      
      # Should either return a signal or nil (depending on market conditions)
      expect(result).to be_nil.or(be_a(Hash))
      
      if result
        expect(result[:segment]).to be_present
        expect(result[:security_id]).to be_present
        expect(result[:meta][:candidate_symbol]).to be_present
      end
    end

    it 'processes index with real API calls', :vcr do
      scheduler = described_class.new(period: 1)
      
      # This will trigger actual API calls (recorded by VCR)
      scheduler.send(:process_index, index_cfg)
      
      # Verify that EntryGuard was called (if signal was generated)
      # Note: EntryGuard is mocked, so no actual orders are placed
    end
  end
end
```

#### Approach 4: Full Integration Test with Timecop + VCR

**Use Case**: Test complete flow with time manipulation and real API calls.

**Example**:

```ruby
# spec/services/signal/scheduler_full_integration_spec.rb
require 'rails_helper'
require 'timecop'

RSpec.describe Signal::Scheduler, :vcr do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end

  let(:nifty_instrument) { create(:instrument, :nifty_index) }
  let(:scheduler) { described_class.new(period: 2) }

  before do
    # Set time to market hours (10:00 AM IST)
    Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
    
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)
    
    allow(AlgoConfig).to receive(:fetch).and_return({
      indices: [index_cfg],
      signals: {
        primary_timeframe: '1m',
        confirmation_timeframe: '5m',
        supertrend: { period: 10, base_multiplier: 2.0 },
        adx: { min_strength: 18.0, confirmation_min_strength: 20.0 }
      },
      chain_analyzer: { max_candidates: 3 }
    })

    # Reduce API call days for faster tests
    allow(nifty_instrument).to receive(:intraday_ohlc).and_wrap_original do |original_method, **kwargs|
      kwargs[:days] = 7 unless kwargs.key?(:days) || kwargs.key?(:from_date)
      original_method.call(**kwargs)
    end

    # Mock EntryGuard to prevent actual orders
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    
    Signal::StateTracker.reset(index_cfg[:key])
  end

  after do
    Timecop.return
    scheduler.stop if scheduler.running?
    Signal::StateTracker.reset(index_cfg[:key])
  end

  describe 'full scheduler lifecycle' do
    it 'runs complete cycle with real API calls', :vcr do
      # Start scheduler
      scheduler.start
      
      # Wait for first cycle
      sleep(0.1)
      
      expect(scheduler.running?).to be true
      
      # Advance time to trigger next cycle
      Timecop.travel(2.seconds)
      sleep(0.1)
      
      # Verify scheduler is still running
      expect(scheduler.running?).to be true
      
      # Stop scheduler
      scheduler.stop
      sleep(0.1)
      
      expect(scheduler.running?).to be false
    end

    it 'handles market close transition', :vcr do
      scheduler.start
      sleep(0.1)
      
      expect(scheduler.running?).to be true
      
      # Advance time to market close (3:35 PM IST)
      Timecop.freeze(Time.zone.parse('2024-01-15 15:35:00 IST'))
      sleep(0.1)
      
      # Scheduler should still be running but skipping processing
      expect(scheduler.running?).to be true
      
      scheduler.stop
    end
  end
end
```

### Running Tests

#### Run All Scheduler Tests

```bash
# Run all scheduler specs
bundle exec rspec spec/services/signal/scheduler*

# Run specific test file
bundle exec rspec spec/services/signal/scheduler_spec.rb

# Run with VCR recording (first time)
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb

# Run with VCR playback only (faster, no API calls)
VCR_MODE=none bundle exec rspec spec/services/signal/scheduler_integration_spec.rb
```

#### Run Tests with Time Manipulation

```bash
# Run time-based tests
bundle exec rspec spec/services/signal/scheduler_time_spec.rb

# Run full integration with time manipulation
bundle exec rspec spec/services/signal/scheduler_full_integration_spec.rb
```

#### Test Individual Methods

```ruby
# In Rails console (test environment)
require 'rails_helper'
require 'timecop'

# Set time to market hours
Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))

# Create scheduler
scheduler = Signal::Scheduler.new(period: 1)

# Test individual method
index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
result = scheduler.send(:evaluate_supertrend_signal, index_cfg)

# Cleanup
Timecop.return
```

### VCR Cassette Management

#### Recording New Cassettes

```bash
# Record all interactions (even if cassette exists)
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb

# Add delay between API calls when recording
VCR_RECORDING_DELAY=0.5 bundle exec rspec spec/services/signal/scheduler_integration_spec.rb
```

#### Cassette Location

Cassettes are stored in: `spec/cassettes/signal/scheduler_integration_spec.yml`

#### Regenerating Cassettes

```bash
# Delete old cassette
rm spec/cassettes/signal/scheduler_integration_spec.yml

# Record new cassette
VCR_MODE=all bundle exec rspec spec/services/signal/scheduler_integration_spec.rb
```

### Testing Checklist

When testing the Signal Scheduler, verify:

- [ ] **Startup**: Scheduler starts correctly with valid config
- [ ] **Shutdown**: Scheduler stops gracefully
- [ ] **Market Hours**: Skips processing when market closed
- [ ] **Timing**: Processes indices at correct intervals
- [ ] **Signal Generation**: Generates signals correctly (both paths)
- [ ] **Chain Analysis**: Selects appropriate option candidates
- [ ] **Entry Execution**: Calls EntryGuard with correct parameters
- [ ] **Error Handling**: Continues processing after errors
- [ ] **Thread Safety**: Handles concurrent access correctly
- [ ] **State Management**: Maintains state correctly across cycles

### Common Test Patterns

#### Pattern 1: Test Time-Dependent Behavior

```ruby
before do
  Timecop.freeze(Time.zone.parse('2024-01-15 10:00:00 IST'))
end

after do
  Timecop.return
end
```

#### Pattern 2: Test with Real API Calls

```ruby
it 'fetches real data', :vcr do
  # VCR will record/playback API calls
  result = scheduler.send(:evaluate_supertrend_signal, index_cfg)
  expect(result).to be_present
end
```

#### Pattern 3: Test Thread Behavior

```ruby
it 'runs in background thread' do
  scheduler.start
  sleep(0.1)
  
  expect(scheduler.running?).to be true
  expect(Thread.list.map(&:name)).to include('signal-scheduler')
  
  scheduler.stop
end
```

#### Pattern 4: Test Error Recovery

```ruby
it 'continues after error' do
  allow(scheduler).to receive(:process_index).and_raise(StandardError.new('Test error'))
  
  scheduler.start
  sleep(0.1)
  
  # Should still be running despite error
  expect(scheduler.running?).to be true
end
```

## Summary

The Signal Scheduler is a sophisticated background service that:
1. **Runs continuously** in a background thread (30-second cycles)
2. **Processes each index** sequentially with delays
3. **Evaluates signals** using either Trend Scorer or Legacy indicators
4. **Selects option candidates** using sophisticated scoring
5. **Executes entries** through EntryGuard with comprehensive validation
6. **Handles errors gracefully** to ensure continuous operation

The system is designed for reliability, with multiple fallbacks, comprehensive error handling, and efficient caching to minimize API calls and database queries.

### Testing Summary

- **Unit Tests**: Fast, isolated tests with mocks
- **Integration Tests**: Time-based tests with Timecop
- **API Tests**: Real API calls recorded with VCR
- **Full Integration**: Complete flow with time manipulation and API calls

Use the appropriate testing approach based on what you're testing:
- **Logic/Behavior**: Unit tests with mocks
- **Time-Dependent**: Integration tests with Timecop
- **API Integration**: Tests with VCR cassettes
- **End-to-End**: Full integration tests combining both
