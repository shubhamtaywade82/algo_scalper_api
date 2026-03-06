# Indicator Parameter Optimization - Complete Guide

## Overview

The optimization engine finds the best parameter combinations for ADX, RSI, MACD, and Supertrend indicators using historical intraday data from DhanHQ. There are two optimization approaches:

1. **Combined Optimization**: Tests ALL indicators together to find best combination (8,748+ combinations)
2. **Single Indicator Optimization**: Tests each indicator separately (15-450 combinations per indicator) - **Recommended**

## Quick Start

### Prerequisites

1. **Run Database Migration**
   ```bash
   rails db:migrate
   ```

   This creates the `best_indicator_params` table if it doesn't exist.

2. **Verify Migration**
   ```bash
   rails db:migrate:status
   ```

   Look for: `20251205203652_create_best_indicator_params.rb`

### Running Optimization

#### Single Indicator Optimization (Recommended)

Optimizes each indicator separately - much faster and clearer:

```bash
# Optimize single timeframe
rails runner scripts/optimize_indicators_separately.rb NIFTY 5 30

# Optimize all timeframes
rails runner scripts/optimize_all_timeframes.rb NIFTY 45
```

Arguments:
- `NIFTY` - Index key (NIFTY, SENSEX, etc.)
- `5` - Timeframe in minutes (1, 5, or 15)
- `30` - Lookback period in days

#### Combined Optimization (NIFTY & SENSEX)

```bash
# Optimize NIFTY and SENSEX with default settings (5m interval, 45 days)
rails runner scripts/optimize_nifty_sensex.rb

# Specify interval and lookback days
rails runner scripts/optimize_nifty_sensex.rb 5 45

# 1-minute interval, 30 days lookback
rails runner scripts/optimize_nifty_sensex.rb 1 30

# 15-minute interval, 90 days lookback
rails runner scripts/optimize_nifty_sensex.rb 15 90
```

## Single Indicator Optimization

### Key Differences from Combined Optimization

**Combined Optimization (Old Approach)**
- Tests ALL indicators together (ADX + RSI + MACD + Supertrend)
- Finds best combination of all parameters
- 8,748+ parameter combinations
- Very slow

**Single Indicator Optimization (New Approach)**
- Tests **each indicator independently**
- Finds best parameters for ADX separately
- Finds best parameters for RSI separately
- Finds best parameters for MACD separately
- Finds best parameters for Supertrend separately
- Much faster (15-450 combinations per indicator)
- Measures **price movement after signals** (max favorable excursion)

### How It Works

1. **Load Historical Data**: Fetches intraday OHLC data for specified timeframe (1m, 5m, 15m) and lookback period (30-45 days)

2. **Generate Signals**: For each indicator, generates buy/sell signals based on indicator parameters

3. **Measure Price Movement**: After each signal, measures the maximum price movement in the next 20 candles:
   - **Buy signals**: Measures upward movement (high - entry price)
   - **Sell signals**: Measures downward movement (entry price - low)

4. **Calculate Metrics**:
   - Average price movement after signals
   - Win rate (percentage of signals with positive movement)
   - Maximum price movement
   - Total number of signals

5. **Optimize**: Tests all parameter combinations and selects the one with highest average price movement

### Parameter Spaces

#### ADX
- `period`: [10, 14, 18]
- `threshold`: [15, 18, 20, 22, 25]
- **Total combinations**: 15

#### RSI
- `period`: [10, 14, 21]
- `oversold`: [20, 25, 30, 35]
- `overbought`: [65, 70, 75, 80]
- **Total combinations**: 48

#### MACD
- `fast`: [8, 12, 14]
- `slow`: [20, 26, 30]
- `signal`: [5, 9, 12]
- **Total combinations**: 27

#### Supertrend
- `atr_period`: [8, 10, 12, 14]
- `multiplier`: [1.5, 2.0, 2.5, 3.0]
- **Total combinations**: 16

### Example Output

```
================================================================================
Single Indicator Parameter Optimization
================================================================================
Index: NIFTY
Interval: 5m
Lookback: 30 days
================================================================================

📊 Instrument: NIFTY (SID: 13)

--------------------------------------------------------------------------------
Optimizing ADX (5m, 30 days)
--------------------------------------------------------------------------------
✅ Optimization Complete (0.6s)

📈 Best Parameters:
   Average Price Move: 0.1876%
   Total Signals: 399
   Win Rate: 98.48%
   Max Move: 1.0464%

⚙️  Parameter Values:
   period: 18
   threshold: 20

--------------------------------------------------------------------------------
Optimizing RSI (5m, 30 days)
--------------------------------------------------------------------------------
✅ Optimization Complete (449.84s)

📈 Best Parameters:
   Average Price Move: 0.2686%
   Total Signals: 78
   Win Rate: 85.90%
   Max Move: 0.5469%

⚙️  Parameter Values:
   period: 21
   oversold: 20
   overbought: 75
```

### Benefits

1. **Faster**: Each indicator optimized separately (15-48 combinations vs 8,748)
2. **Clearer**: Know exactly which parameters work best for each indicator
3. **Focused**: Measures price movement after signals (what you care about)
4. **Flexible**: Can use best parameters for each indicator independently in your strategy

## Combined Optimization

### Architecture

#### ✅ Uses Your Existing Infrastructure

- **CandleSeries Objects**: Uses `instrument.candles(interval:)` or `instrument.intraday_ohlc()` → `CandleSeries`
- **Indicator Methods**: Uses existing `CandleSeries` methods and `Indicators::Supertrend` service
- **Candle Objects**: Works with `@series.candles` array of `Candle` objects
- **Zero Duplication**: No fake OHLC hashes or duplicate indicator calculations

#### Indicator Implementation

| Indicator | Method | Returns |
|-----------|--------|---------|
| **ADX** | `TechnicalAnalysis::Adx.calculate(@series.hlc, period: 14)` | Array of objects with `.adx`, `.plus_di`, `.minus_di` |
| **RSI** | `partial_series.rsi(period)` per-index | Single value (calculated on partial series) |
| **MACD** | `RubyTechnicalAnalysis::Macd.new(series: closes, ...).call` | `[macd_array, signal_array, histogram_array]` |
| **Supertrend** | `Indicators::Supertrend.new(series: @series, ...).call` | `{ trend: :bullish/:bearish, line: [...] }` |

### Critical: ADX Directional Logic

#### ⚠️ **ADX Theory (Correct)**

**ADX NEVER gives direction. It gives ONLY trend strength.**

| Component | Purpose | Meaning |
|-----------|---------|---------|
| **ADX** | Trend Strength | Higher ADX = stronger trend (regardless of direction) |
| **DI+ (Plus DI)** | Upward Direction | Measures upward price movement strength |
| **DI− (Minus DI)** | Downward Direction | Measures downward price movement strength |

#### Correct Signal Logic

**Long Signal (BUY):**
1. ✅ **ADX ≥ threshold** → Strong trend exists
2. ✅ **DI+ > DI−** → Trend direction is UP
3. ✅ **RSI ≤ oversold** → Pullback opportunity
4. ✅ **MACD bullish** → Momentum confirms
5. ✅ **Supertrend bullish** → Structure confirms

**Short Signal (SELL):**
1. ✅ **ADX ≥ threshold** → Strong trend exists
2. ✅ **DI− > DI+** → Trend direction is DOWN
3. ✅ **RSI ≥ overbought** → Overextension
4. ✅ **MACD bearish** → Momentum confirms
5. ✅ **Supertrend bearish** → Structure confirms

### Default Parameter Space

```ruby
PARAM_SPACE = {
  adx_thresh: [18, 22, 25, 28],
  rsi_lo: [20, 25, 30],
  rsi_hi: [65, 70, 75],
  macd_fast: [8, 12, 14],
  macd_slow: [20, 26, 30],
  macd_signal: [5, 9, 12],
  st_atr: [8, 10, 12],
  st_mult: [1.5, 2.0, 2.5]
}
```

**Total combinations**: 8,748

## Database Schema

### Migration: `db/migrate/20251205203652_create_best_indicator_params.rb`

```ruby
create_table :best_indicator_params do |t|
  t.references :instrument, null: false, foreign_key: true, index: true
  t.string :interval, null: false                    # "1", "5", "15"
  t.string :indicator, null: false                  # "adx", "rsi", "macd", "supertrend" (for single indicator)
  t.jsonb :params, null: false, default: {}         # Indicator parameters
  t.jsonb :metrics, null: false, default: {}         # Performance metrics
  t.decimal :score, precision: 12, scale: 6, null: false, default: 0
  t.timestamps
end

# Unique constraint: exactly ONE row per instrument + interval + indicator
add_index :best_indicator_params,
          [:instrument_id, :interval, :indicator],
          unique: true,
          name: "idx_unique_best_params_per_instrument_interval_indicator"

# JSONB search optimizations
add_index :best_indicator_params, :params, using: :gin
add_index :best_indicator_params, :metrics, using: :gin
```

**Key Feature**: Unique constraint ensures **one canonical best result** per instrument+interval+indicator. New optimizations **overwrite** existing rows via upsert.

### Model: `app/models/best_indicator_param.rb`

```ruby
class BestIndicatorParam < ApplicationRecord
  belongs_to :instrument

  validates :interval, presence: true
  validates :indicator, presence: true
  validates :params, presence: true
  validates :metrics, presence: true
  validates :score, presence: true

  # Fetch canonical best params for specific indicator
  scope :best_for_indicator, ->(instrument_id, interval, indicator) do
    where(instrument_id: instrument_id, interval: interval, indicator: indicator).limit(1)
  end

  # Fetch all optimized indicators for instrument + timeframe
  scope :for_instrument_interval, ->(instrument_id, interval) do
    where(instrument_id: instrument_id, interval: interval)
  end
end
```

## Services

### 1. `Optimization::IndicatorOptimizer` (Combined)

Main orchestrator that:
- Loads historical data via `instrument.intraday_ohlc(days: @lookback)`
- Generates parameter combinations
- Tests each combination via `StrategyBacktester`
- Tracks best result by Sharpe ratio
- Persists via upsert (updates existing or creates new)

### 2. `Optimization::SingleIndicatorOptimizer` (Single)

Optimizes each indicator separately:
- Loads historical data
- Tests parameter combinations for one indicator
- Measures price movement after signals
- Tracks best result by average price movement
- Persists via upsert

### 3. `Optimization::StrategyBacktester`

Backtesting engine that:
- Calculates indicators using existing methods
- Generates trades from signals
- Tracks price movement after signals
- Returns trade list for metrics calculation

**Signal Generation:**
- Minimum lookback: `max(st_atr, macd_slow, 30)`
- All indicators must have valid values
- Direction determined by DI+ vs DI− comparison
- Strength determined by ADX threshold

### 4. `Optimization::MetricsCalculator`

Calculates performance metrics:
- **Sharpe Ratio** (optimization target for combined)
- **Average Price Movement** (optimization target for single)
- Win Rate
- Expectancy
- Net PnL

## Usage Examples

### Basic Usage (Combined)

```ruby
# Get instrument
instrument = Instrument.find_by(symbol_name: "NIFTY 50")
# Or via IndexInstrumentCache
index_cfg = AlgoConfig.fetch[:indices].find { |i| i[:key] == "NIFTY" }
instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)

# Run optimization
result = Optimization::IndicatorOptimizer.new(
  instrument: instrument,
  interval: "5",           # "1", "5", or "15"
  lookback_days: 45        # 1-180 days
).run

# Result structure
{
  score: 1.82,             # Sharpe ratio
  params: {
    adx_thresh: 25,
    rsi_lo: 30,
    rsi_hi: 70,
    macd_fast: 12,
    macd_slow: 26,
    macd_signal: 9,
    st_atr: 10,
    st_mult: 2.5
  },
  metrics: {
    win_rate: 0.41,
    sharpe: 1.82,
    expectancy: 6.4,
    net_pnl: 821.50,
    avg_move: 6.71
  }
}
```

### Retrieving Results

#### Get Best Parameters for Specific Indicator (Single Indicator)

```ruby
# Get best ADX parameters for NIFTY 5m
best = BestIndicatorParam.best_for_indicator(instrument.id, '5', 'adx').first
params = best.params
# => { "period" => 18, "threshold" => 20 }

# Get best RSI parameters
best = BestIndicatorParam.best_for_indicator(instrument.id, '5', 'rsi').first
params = best.params
# => { "period" => 21, "oversold" => 20, "overbought" => 75 }
```

#### Get All Optimized Indicators for Instrument + Timeframe

```ruby
all = BestIndicatorParam.for_instrument_interval(instrument.id, '5')
all.each do |result|
  puts "#{result.indicator}: #{result.score.round(4)}%"
  puts "  Params: #{result.params.inspect}"
end
```

#### Get Best Parameters (Combined)

```ruby
# Get canonical best params (always exactly ONE)
best = BestIndicatorParam.best_for(instrument.id, "5").first

return unless best

# Use optimized parameters
params  = best.params     # { adx_thresh: 25, rsi_lo: 30, ... }
metrics = best.metrics    # { win_rate: 0.41, sharpe: 1.82, ... }
score   = best.score      # 1.82 (Sharpe ratio)

# Apply to signal generation
adx_threshold = params['adx_thresh'] || params[:adx_thresh]
rsi_oversold = params['rsi_lo'] || params[:rsi_lo]
rsi_overbought = params['rsi_hi'] || params[:rsi_hi]
# ... etc
```

## Parameters Explained

### ADX Threshold (`adx_thresh`)
- **Range**: 18-30 (typical: 20-25)
- **Meaning**: Minimum ADX strength required for signal
- **Higher**: Fewer but stronger trend signals
- **Lower**: More signals, may include weak trends

### RSI Levels
- **`rsi_lo`** (Oversold): 20-30
  - Lower = more buy signals
  - Higher = fewer but stronger buy signals
- **`rsi_hi`** (Overbought): 65-75
  - Higher = more sell signals
  - Lower = fewer but stronger sell signals

### MACD Parameters
- **`macd_fast`**: 8-14 (default: 12) - Faster EMA period
- **`macd_slow`**: 20-30 (default: 26) - Slower EMA period
- **`macd_signal`**: 5-12 (default: 9) - Signal line EMA period

### Supertrend Parameters
- **`st_atr`** (ATR Period): 8-14 (default: 10) - Volatility measurement period
- **`st_mult`** (Multiplier): 1.5-3.0 (default: 2.0-2.5) - Distance from ATR for trend line

## Performance Metrics

### Primary Metrics

1. **Sharpe Ratio** (Combined Optimization Target)
   - Risk-adjusted return
   - Higher is better
   - Target: > 1.0 (good), > 1.5 (excellent)

2. **Average Price Movement** (Single Indicator Target)
   - Average price movement after signals
   - Higher is better
   - Measures max favorable excursion

3. **Win Rate**
   - Percentage of profitable trades
   - Target: > 40% (for options trading)

4. **Expectancy**
   - Average expected return per trade
   - Target: > 0 (positive expectancy)

5. **Net PnL**
   - Total profit/loss
   - Uses actual price movement

## Best Practices

### 1. Start Conservative

Test with smaller parameter space first:
```ruby
small_params = {
  adx_thresh: [22, 25, 28],
  rsi_lo: [25, 30],
  rsi_hi: [70, 75],
  # ... fewer combinations
}
```

### 2. Use Appropriate Lookback

- **1 month**: Quick test, recent market conditions
- **3 months**: Balanced, captures recent trends
- **6 months**: Comprehensive, includes more market regimes

### 3. Test Multiple Timeframes

```ruby
%w[1 5 15].each do |interval|
  result = Optimization::IndicatorOptimizer.new(
    instrument: instrument,
    interval: interval,
    lookback_days: 45
  ).run

  puts "#{interval}m: Sharpe=#{result[:score]&.round(3)}"
end
```

### 4. Validate Results

- Check if best parameters make logical sense
- Verify win rate is reasonable (> 35%)
- Ensure Sharpe > 1.0 (for combined)
- Review trade count (too few = overfitting risk)

## Performance Considerations

### Optimization Speed

- **Small dataset** (< 1000 candles): ~1-2 minutes
- **Medium dataset** (1000-5000 candles): ~5-10 minutes
- **Large dataset** (> 5000 candles): ~15-30 minutes

### Reducing Computation Time

1. **Limit parameter space**: Fewer combinations = faster
2. **Shorter lookback**: Less data = faster
3. **Run during off-hours**: Background job recommended
4. **Use single indicator optimization**: Much faster than combined

### Running as Background Job

```ruby
# In Sidekiq job
class IndicatorOptimizationJob < ApplicationJob
  def perform(instrument_id, interval, lookback_days)
    instrument = Instrument.find(instrument_id)

    result = Optimization::IndicatorOptimizer.new(
      instrument: instrument,
      interval: interval,
      lookback_days: lookback_days
    ).run

    Rails.logger.info("Optimization complete: #{result.inspect}")
  end
end
```

Schedule it:

```ruby
# Schedule nightly optimization
IndicatorOptimizationJob.perform_async('NIFTY', '5', 45)
IndicatorOptimizationJob.perform_async('SENSEX', '5', 45)
```

## Expected Output

```
================================================================================
Indicator Parameter Optimization - NIFTY & SENSEX
================================================================================
Interval: 5m
Lookback: 45 days
================================================================================

--------------------------------------------------------------------------------
Optimizing NIFTY (5m, 45 days)
--------------------------------------------------------------------------------
📊 Instrument: NIFTY 50 (SID: 13)
🔄 Starting optimization...
[Optimization] Starting optimization for NIFTY 50 @ 5m (45 days)
[Optimization] Loaded 2340 candles
[Optimization] Testing 2592 parameter combinations...
[Optimization] Progress: 10% (259/2592)
[Optimization] New best: Sharpe=1.234, WR=0.412, PnL=456.78 (259/2592)
...
[Optimization] Optimization complete. Best Sharpe: 1.456

✅ Optimization Complete (1234.56s)

📈 Best Parameters:
   Sharpe Ratio: 1.456
   Win Rate: 41.23%
   Expectancy: 6.45
   Net PnL: 821.50
   Avg Move: 6.71%

⚙️  Parameter Values:
   adx_thresh: 25
   rsi_lo: 30
   rsi_hi: 70
   macd_fast: 12
   macd_slow: 26
   macd_signal: 9
   st_atr: 10
   st_mult: 2.5

💾 Saved to database:
   Score: 1.456
   Updated: 2025-12-05 21:00:00 UTC
```

## Troubleshooting

### Table Missing Error
```bash
rails db:migrate
```

### No Data Available
- Check if DhanHQ API is accessible
- Verify instrument security IDs in `algo.yml`
- Check network connectivity

### Optimization Takes Too Long
- Reduce lookback days (e.g., 30 instead of 90)
- Reduce parameter space (edit `PARAM_SPACE` in `IndicatorOptimizer`)
- Run one index at a time
- Use single indicator optimization instead

### No Trades Generated
- Parameters may be too strict
- Try different timeframes
- Check if historical data has sufficient volatility
- Lower ADX threshold, widen RSI bands

### All Negative Results
- Market conditions not suitable for strategy
- Try different timeframes or lookback periods

### Overfitting Warning
- Too many parameters, too few trades
- Simplify parameter space, use walk-forward validation

### Memory Issues
- Large dataset with many combinations
- Reduce lookback period or parameter space

## Architecture Benefits

✅ **Zero duplicates** - Unique constraint enforced at DB level
✅ **Fast lookup** - Single row per instrument+interval+indicator
✅ **Upsert-based updates** - Atomic insert/update
✅ **JSONB flexibility** - Store any parameter/metric structure
✅ **GIN indexes** - Fast JSONB queries
✅ **Rails native** - Uses ActiveRecord upsert
✅ **PostgreSQL optimized** - Unique index + JSONB indexes
✅ **Correct ADX logic** - Uses DI+/DI- for direction
✅ **Uses existing infrastructure** - No duplication

## Files

1. **`app/services/optimization/indicator_optimizer.rb`** - Combined optimization orchestrator
2. **`app/services/optimization/single_indicator_optimizer.rb`** - Single indicator optimizer
3. **`app/services/optimization/single_indicator_backtester.rb`** - Single indicator backtester
4. **`app/services/optimization/strategy_backtester.rb`** - Combined backtesting engine
5. **`app/services/optimization/metrics_calculator.rb`** - Metrics calculator
6. **`app/models/best_indicator_param.rb`** - Database model
7. **`db/migrate/20251205203652_create_best_indicator_params.rb`** - Migration
8. **`scripts/optimize_nifty_sensex.rb`** - Combined optimization script
9. **`scripts/optimize_indicators_separately.rb`** - Single indicator optimization script
10. **`scripts/optimize_all_timeframes.rb`** - Multi-timeframe optimization script

## Next Steps

After optimization:
1. Review results in database
2. Validate parameters make logical sense
3. Test with paper trading
4. Integrate into live signal generation
5. Set up automated re-optimization schedule

### Optional Enhancements

1. **Sidekiq Nightly Scheduler** - Auto-optimize daily with locking
2. **Dashboard API Endpoint** - View optimization results
3. **Redis Fast-Cache Layer** - Ultra-fast parameter access
4. **Composite Scoring** - Sharpe + Expectancy weighted model
5. **Bayesian Optimization** - Replace brute-force with smarter search
6. **Parameter Drift Detection** - Auto-retrain when performance degrades
7. **Walk-Forward Testing** - Validate on out-of-sample data

