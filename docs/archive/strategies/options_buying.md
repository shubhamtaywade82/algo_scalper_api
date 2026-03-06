# Options Buying Strategies Implementation

## Overview

This document describes the implementation of four options buying strategies integrated into the algo_scalper_api system:

1. **Option Buying using Open Interest** (Strategy 6.3)
2. **Momentum Buying Option** (Strategy 6.6)
3. **Maximizing Momentum with the BTST Option Buying Strategy** (Strategy 6.10)
4. **Swing Buying: A Winning Options Trading Strategy** (Strategy 6.13)

## Architecture

### Core Components

#### 1. `Options::DerivativeChainAnalyzer`

**Location**: `app/services/options/derivative_chain_analyzer.rb`

**Purpose**: Analyzes option chains using Derivative records from the database, merging with live tick data and API chain data.

**Key Features**:
- Uses existing `Derivative` model records (no duplicate storage)
- Integrates with `Live::TickCache` and `Live::RedisTickCache` for real-time data
- Merges API option chain data (OI, IV, Greeks) with live ticks (LTP, bid/ask)
- Scores options based on multiple factors: OI, spread, IV, volume, ATM proximity
- Returns candidates with full Derivative records for order placement

**Usage**:
```ruby
analyzer = Options::DerivativeChainAnalyzer.new(
  index_key: :NIFTY,
  expiry: nil, # Auto-selects nearest expiry
  config: AlgoConfig.fetch[:chain_analyzer]
)

candidates = analyzer.select_candidates(limit: 5, direction: :bullish)
# Returns: Array of hashes with :derivative, :security_id, :segment, :score, etc.
```

**Configuration** (`config/algo.yml`):
```yaml
chain_analyzer:
  max_candidates: 2
  strike_distance_pct: 0.02  # Max 2% from spot
  min_oi: 10000
  min_iv: 5.0
  max_iv: 60.0
  max_spread_pct: 0.03  # 3%
  scoring_weights:
    oi: 0.4
    spread: 0.25
    iv: 0.2
    volume: 0.15
```

#### 2. Strategy Engines

All strategy engines inherit from `Signal::Engines::BaseEngine` and implement the `evaluate` method.

**Location**: `app/services/signal/engines/`

**Existing Engines**:
- `OpenInterestBuyingEngine` - Strategy 6.3
- `MomentumBuyingEngine` - Strategy 6.6
- `BtstMomentumEngine` - Strategy 6.10
- `SwingOptionBuyingEngine` - Strategy 6.13

**How They Work**:
1. Receive `option_candidate` from `DerivativeChainAnalyzer`
2. Access live tick data via `option_tick` method (from BaseEngine)
3. Evaluate strategy-specific conditions
4. Return signal hash via `create_signal` method

**Example**:
```ruby
# OpenInterestBuyingEngine evaluates:
# - OI increase from last state
# - Price > previous close
# Returns signal if conditions met
```

#### 3. Signal Scheduler Integration

**Location**: `app/services/signal/scheduler.rb`

**Flow**:
1. Scheduler runs every 30 seconds
2. For each index, loads enabled strategies by priority
3. Uses `DerivativeChainAnalyzer` to get candidates
4. Evaluates each strategy in priority order
5. First strategy that emits a signal triggers order placement

**Configuration** (`config/algo.yml`):
```yaml
indices:
  - key: NIFTY
    strategies:
      open_interest:
        enabled: true
        priority: 1
        capital_alloc_pct: 0.20
      momentum_buying:
        enabled: true
        priority: 2
        min_rsi: 60
      btst:
        enabled: true
        priority: 3
      swing_buying:
        enabled: true
        priority: 4
```

## Data Flow

```
1. Signal::Scheduler (every 30s)
   ↓
2. Options::DerivativeChainAnalyzer.select_candidates()
   ↓
3. Load Derivative records for index + expiry
   ↓
4. Fetch API option chain (OI, IV, Greeks)
   ↓
5. Merge with Live::RedisTickCache (LTP, bid/ask, OI change)
   ↓
6. Score and rank options
   ↓
7. Return top candidates
   ↓
8. Strategy Engine evaluates candidate
   ↓
9. If signal generated → OrderRouter → DhanHQ API
```

## Strategy Details

### 1. Open Interest Buying (Strategy 6.3)

**Engine**: `Signal::Engines::OpenInterestBuyingEngine`

**Logic**:
- Monitors OI change from last evaluation
- Requires: `current_oi > last_oi` AND `price > prev_close`
- Indicates: Smart money accumulation

**Configuration**:
```yaml
open_interest:
  enabled: true
  priority: 1
  capital_alloc_pct: 0.20
```

### 2. Momentum Buying (Strategy 6.6)

**Engine**: `Signal::Engines::MomentumBuyingEngine`

**Logic**:
- Checks if `ltp > day_high` (breakout)
- Optional RSI filter: `rsi > min_rsi` (default: 60)
- Indicates: Strong momentum continuation

**Configuration**:
```yaml
momentum_buying:
  enabled: true
  priority: 2
  min_rsi: 60
```

### 3. BTST Momentum (Strategy 6.10)

**Engine**: `Signal::Engines::BtstMomentumEngine`

**Logic**:
- Only active during EOD window (15:10 - 15:20 IST)
- Requires: `ltp > vwap` AND `volume > avg_volume`
- Indicates: End-of-day momentum for next-day gap

**Configuration**:
```yaml
btst:
  enabled: true
  priority: 3
```

### 4. Swing Buying (Strategy 6.13)

**Engine**: `Signal::Engines::SwingOptionBuyingEngine`

**Logic**:
- Requires: Higher timeframe Supertrend = UP
- Price between EMA9 and EMA21
- Price > previous high
- Indicates: Swing trend continuation

**Configuration**:
```yaml
swing_buying:
  enabled: true
  priority: 4
```

## Integration Points

### Derivative Records

The system uses existing `Derivative` model records which contain:
- `security_id` - For order placement
- `segment` - Exchange segment
- `strike_price` - Strike price
- `option_type` - CE or PE
- `expiry_date` - Expiry date
- `lot_size` - Lot size for position sizing
- `underlying_symbol` - Links to index

### Tick Cache Integration

- `Live::TickCache` - In-memory cache (fastest)
- `Live::RedisTickCache` - Redis-backed cache (persistent, HA)
- Provides: LTP, bid, ask, OI, OI change, volume, Greeks

### Order Placement

When a strategy emits a signal:
1. `Signal::Scheduler` receives signal with `security_id` and `segment`
2. `Entries::EntryGuard` validates entry conditions
3. `Orders::Router` places market BUY order via DhanHQ API
4. `PositionTracker` tracks the position
5. `Live::RiskManagerService` manages exits (SL/TP/trailing)

## Configuration Reference

### Chain Analyzer Settings

```yaml
chain_analyzer:
  max_candidates: 2              # Max candidates per evaluation
  strike_distance_pct: 0.02      # Max 2% from spot
  min_oi: 10000                   # Minimum OI
  min_iv: 5.0                     # Minimum IV (%)
  max_iv: 60.0                    # Maximum IV (%)
  max_spread_pct: 0.03            # Max 3% spread
  scoring_weights:
    oi: 0.4                       # OI weight (40%)
    spread: 0.25                  # Spread weight (25%)
    iv: 0.2                       # IV weight (20%)
    volume: 0.15                # Volume weight (15%)
```

### Strategy Priority

Strategies are evaluated in priority order (lower number = higher priority):
1. Open Interest (priority: 1)
2. Momentum Buying (priority: 2)
3. BTST (priority: 3)
4. Swing Buying (priority: 4)

First strategy that emits a signal wins (no multiple entries per cycle).

## Important Notes

### Scoring Function

The scoring function is **heuristic** and must be backtested. Default weights are starting points only. Adjust based on:
- Historical performance
- Market conditions
- Index-specific characteristics

### Data Quality

- **Provider data quality matters**: Noisy or stale OI/volume will destroy ranking quality
- Ensure WebSocket feed populates OI/volume reliably
- Cache option chain data (5s-30s) to respect rate limits

### Risk Management

- **Avoid aggressive orders for thin strikes**: Always check OI and volume
- **Enforce lot-size rounding**: Use exchange lot sizes
- **Rate limits**: Do not call DhanHQ option chain every second
- Use incremental updates via WebSocket when available

### IV Units

- IV comes as percent or decimal from providers
- This implementation uses plain numeric as percent (e.g., 20.5 = 20.5%)

## Testing

Run tests:
```bash
# Test ChainAnalyzer
bundle exec rspec spec/services/options/derivative_chain_analyzer_spec.rb

# Test Strategy Engines
bundle exec rspec spec/services/signal/engines/

# Integration test
bundle exec rspec spec/integration/options_buying_strategies_spec.rb
```

## Future Enhancements

1. **Backtesting**: Implement backtesting for scoring weights
2. **IV Rank**: Add IV rank calculation for better IV filtering
3. **Greeks Analysis**: Use delta/gamma/theta for better selection
4. **Multi-Expiry**: Support weekly + monthly expiry selection
5. **Strategy-Specific Filters**: Allow each strategy to specify its own chain filters

