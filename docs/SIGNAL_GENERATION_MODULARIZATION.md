# Signal Generation Flow - Modularization Analysis

## Executive Summary

This document analyzes the current signal generation flow and provides recommendations for making it modular, allowing:
- Individual indicator toggling (enable/disable)
- Multiple indicator combinations
- Configurable indicator weights/confidence scoring
- Easy addition of new indicators

---

## Current Signal Generation Flow

### 1. Entry Points

There are **two main entry points** for signal generation:

#### A. `Signal::Scheduler` (Primary - Used in Production)
- **Location**: `app/services/signal/scheduler.rb`
- **Flow**:
  1. Calls `evaluate_supertrend_signal(index_cfg)` every 30 seconds
  2. Checks if `trend_scorer_enabled?` feature flag is true
  3. If enabled → Uses `Signal::TrendScorer.compute_direction()`
  4. If disabled → Falls back to `Signal::Engine.analyze_multi_timeframe()`
  5. Selects option candidate from chain
  6. Calls `Entries::EntryGuard.try_enter()`

#### B. `Signal::Engine.run_for()` (Legacy/Alternative)
- **Location**: `app/services/signal/engine.rb`
- **Flow**:
  1. Checks for strategy recommendations (if enabled)
  2. If strategy-based → Uses `analyze_with_recommended_strategy()`
  3. Else → Uses `analyze_timeframe()` with Supertrend + ADX
  4. Optionally applies confirmation timeframe
  5. Runs comprehensive validation
  6. Creates `TradingSignal` record
  7. Picks strikes and calls `Entries::EntryGuard.try_enter()`

---

## Current Indicators Used

### 1. **TrendScorer Path** (`Signal::TrendScorer`)

Located in: `app/services/signal/trend_scorer.rb`

#### Indicators Used (Hardcoded):
1. **RSI** (Relative Strength Index)
   - Period: 14 (hardcoded)
   - Used in: `ind_score()` method (0-2 points)
   - Logic: `rsi > 50 && rsi < 70` → 2.0 points, `rsi > 40 && rsi < 80` → 1.0 point
   - Also used in: `mtf_score()` for multi-timeframe alignment

2. **MACD** (Moving Average Convergence Divergence)
   - Periods: 12, 26, 9 (hardcoded)
   - Used in: `ind_score()` method (0-2 points)
   - Logic: `macd_line > signal && histogram > 0` → 2.0 points

3. **ADX** (Average Directional Index)
   - Period: 14 (hardcoded)
   - Used in: `ind_score()` method (0-2 points)
   - Logic: `adx > 25` → 2.0 points, `adx > 20` → 1.0 point, `adx > 15` → 0.5 points
   - Also used in: `mtf_score()` for multi-timeframe alignment

4. **Supertrend**
   - Period: 10, Multiplier: 2.0 (hardcoded in `ind_score()`)
   - Used in: `ind_score()` method (0-1 point)
   - Logic: `trend == :bullish` → 1.0 point
   - Also used in: `mtf_score()` for trend alignment (0-3 points)

5. **Price Action Patterns** (in `pa_score()`)
   - Momentum calculation (last 3 vs previous 3 candles)
   - Structure breaks (swing highs/lows)
   - Candle patterns (bullish candles, higher highs)
   - Trend consistency (increasing closes)

#### Scoring System:
- **PA Score**: 0-7 points (Price Action)
- **IND Score**: 0-7 points (Indicators: RSI, MACD, ADX, Supertrend)
- **MTF Score**: 0-7 points (Multi-Timeframe alignment)
- **Total**: 0-21 points
- **Thresholds**:
  - Bullish: `>= 14.0` (configurable via `min_trend_score`)
  - Bearish: `<= 7.0` (hardcoded)

### 2. **Engine Path** (`Signal::Engine`)

Located in: `app/services/signal/engine.rb`

#### Indicators Used:
1. **Supertrend**
   - Configurable via `signals.supertrend` in `algo.yml`
   - Default: `period: 7, base_multiplier: 3.0`
   - Used in: `analyze_timeframe()` method
   - Determines direction: `:bullish` or `:bearish`

2. **ADX** (Average Directional Index)
   - Period: 14 (hardcoded)
   - Configurable threshold via `signals.adx.min_strength` (default: 18)
   - Used as filter: If `adx < min_strength` → `:avoid`
   - Can be toggled via `enable_adx_filter: true/false`

3. **Multi-Timeframe Confirmation**
   - Primary timeframe: `1m` (configurable)
   - Confirmation timeframe: `5m` (configurable)
   - Logic: Both must align, else `:avoid`

#### Validation Checks (in `comprehensive_validation()`):
1. **IV Rank Check** (optional, mode-dependent)
2. **Theta Risk Assessment** (optional, mode-dependent)
3. **ADX Strength** (if `enable_adx_filter: true`)
4. **Trend Confirmation** (optional, mode-dependent)
5. **Market Timing** (always required)

---

## Current Architecture Issues

### 1. **Hardcoded Indicators**
- Indicator periods are hardcoded (RSI: 14, MACD: 12/26/9, ADX: 14)
- Indicator thresholds are hardcoded (RSI > 50, ADX > 25, etc.)
- Indicator weights are hardcoded (RSI: 0-2 points, MACD: 0-2 points, etc.)

### 2. **No Toggle Mechanism**
- Cannot disable individual indicators (e.g., disable MACD but keep RSI)
- Cannot disable price action scoring
- Cannot disable multi-timeframe scoring

### 3. **Tight Coupling**
- `TrendScorer.ind_score()` directly calls `Indicators::Calculator` methods
- Scoring logic is embedded in `TrendScorer` class
- Cannot easily swap indicator implementations

### 4. **No Indicator Registry**
- No central place to register/configure indicators
- No way to add new indicators without modifying core classes
- No way to define indicator combinations

### 5. **Mixed Responsibilities**
- `TrendScorer` calculates indicators AND scores them
- `Engine` calculates indicators AND decides direction
- No separation between indicator calculation and signal generation

### 6. **Limited Configuration**
- Only Supertrend and ADX are configurable via `algo.yml`
- RSI, MACD parameters are not configurable
- Indicator weights are not configurable

---

## Recommended Modular Architecture

### 1. **Indicator Registry Pattern**

Create a registry system where indicators can be:
- Registered with configuration
- Enabled/disabled per index or globally
- Combined with weights/confidence scores

#### Proposed Structure:

```
app/services/indicators/
  ├── registry.rb              # Central indicator registry
  ├── base.rb                  # Base indicator interface
  ├── rsi_indicator.rb         # RSI indicator implementation
  ├── macd_indicator.rb        # MACD indicator implementation
  ├── adx_indicator.rb         # ADX indicator implementation
  ├── supertrend_indicator.rb  # Supertrend indicator (wrapper)
  ├── price_action_indicator.rb # Price action patterns
  └── composite_indicator.rb   # Combines multiple indicators
```

### 2. **Indicator Interface**

Each indicator should implement:

```ruby
module Indicators
  class Base
    def initialize(series:, config: {})
      @series = series
      @config = config
    end

    # Calculate indicator value
    def calculate
      raise NotImplementedError
    end

    # Get signal direction (:bullish, :bearish, :neutral, :avoid)
    def signal_direction
      raise NotImplementedError
    end

    # Get confidence score (0.0-1.0)
    def confidence_score
      raise NotImplementedError
    end

    # Get raw indicator value
    def value
      raise NotImplementedError
    end

    # Check if indicator is ready (enough data)
    def ready?
      raise NotImplementedError
    end
  end
end
```

### 3. **Configuration Structure**

Add to `config/algo.yml`:

```yaml
signals:
  indicators:
    # Global indicator settings
    enabled_indicators:
      - rsi
      - macd
      - adx
      - supertrend
      - price_action

    # Per-indicator configuration
    rsi:
      enabled: true
      period: 14
      weight: 0.2  # Weight in composite score
      thresholds:
        strong_bullish: { min: 50, max: 70 }
        moderate_bullish: { min: 40, max: 80 }
        weak_bullish: { min: 30, max: 100 }

    macd:
      enabled: true
      fast_period: 12
      slow_period: 26
      signal_period: 9
      weight: 0.2
      require_histogram: true

    adx:
      enabled: true
      period: 14
      weight: 0.2
      min_strength: 18
      thresholds:
        very_strong: 40
        strong: 25
        moderate: 15

    supertrend:
      enabled: true
      period: 7
      base_multiplier: 3.0
      weight: 0.3

    price_action:
      enabled: true
      weight: 0.1
      patterns:
        - momentum
        - structure_breaks
        - candle_patterns
        - trend_consistency

    # Composite scoring
    composite:
      mode: weighted_sum  # or: majority_vote, all_must_agree, any_one
      min_confidence: 0.6
      require_min_indicators: 2  # Minimum number of indicators that must agree
```

### 4. **Indicator Registry**

```ruby
module Indicators
  class Registry
    include Singleton

    def initialize
      @indicators = {}
      @enabled_indicators = []
    end

    def register(name, indicator_class, config = {})
      @indicators[name.to_sym] = {
        class: indicator_class,
        config: config
      }
    end

    def enabled?(name)
      @enabled_indicators.include?(name.to_sym)
    end

    def enable(name)
      @enabled_indicators << name.to_sym unless enabled?(name)
    end

    def disable(name)
      @enabled_indicators.delete(name.to_sym)
    end

    def create(name, series:, config: {})
      indicator_def = @indicators[name.to_sym]
      return nil unless indicator_def

      indicator_def[:class].new(series: series, config: config.merge(indicator_def[:config]))
    end

    def calculate_all(series, config_overrides: {})
      @enabled_indicators.map do |name|
        indicator = create(name, series: series, config: config_overrides[name] || {})
        next nil unless indicator&.ready?

        {
          name: name,
          indicator: indicator,
          direction: indicator.signal_direction,
          confidence: indicator.confidence_score,
          value: indicator.value
        }
      end.compact
    end
  end
end
```

### 5. **Composite Indicator**

```ruby
module Indicators
  class Composite < Base
    MODES = {
      weighted_sum: :calculate_weighted_sum,
      majority_vote: :calculate_majority_vote,
      all_must_agree: :calculate_all_must_agree,
      any_one: :calculate_any_one
    }.freeze

    def initialize(series:, indicators:, mode: :weighted_sum, config: {})
      super(series: series, config: config)
      @indicators = indicators
      @mode = mode.to_sym
    end

    def signal_direction
      case @mode
      when :weighted_sum
        calculate_weighted_sum_direction
      when :majority_vote
        calculate_majority_vote_direction
      when :all_must_agree
        calculate_all_must_agree_direction
      when :any_one
        calculate_any_one_direction
      end
    end

    def confidence_score
      case @mode
      when :weighted_sum
        calculate_weighted_sum_confidence
      else
        calculate_majority_confidence
      end
    end

    private

    def calculate_weighted_sum_direction
      bullish_score = 0.0
      bearish_score = 0.0

      @indicators.each do |indicator_result|
        weight = indicator_result[:weight] || 1.0
        direction = indicator_result[:direction]
        confidence = indicator_result[:confidence] || 0.5

        case direction
        when :bullish
          bullish_score += weight * confidence
        when :bearish
          bearish_score += weight * confidence
        end
      end

      return :bullish if bullish_score > bearish_score && bullish_score > @config[:min_confidence] || 0.5
      return :bearish if bearish_score > bullish_score && bearish_score > @config[:min_confidence] || 0.5

      :avoid
    end

    # ... other mode implementations
  end
end
```

### 6. **Refactored TrendScorer**

```ruby
module Signal
  class TrendScorer
    def ind_score(series)
      return 0 unless series&.candles&.any?

      # Get enabled indicators from registry
      indicators_cfg = AlgoConfig.fetch.dig(:signals, :indicators) || {}
      enabled = indicators_cfg[:enabled_indicators] || []

      # Calculate all enabled indicators
      indicator_results = Indicators::Registry.instance.calculate_all(
        series,
        config_overrides: indicators_cfg
      )

      # Filter to only enabled indicators
      indicator_results = indicator_results.select { |r| enabled.include?(r[:name].to_s) }

      # Use composite indicator to combine results
      composite = Indicators::Composite.new(
        series: series,
        indicators: indicator_results,
        mode: indicators_cfg.dig(:composite, :mode) || :weighted_sum,
        config: indicators_cfg[:composite] || {}
      )

      # Convert composite confidence (0-1) to score (0-7)
      (composite.confidence_score * 7.0).round(1)
    end
  end
end
```

---

## Implementation Plan

### Phase 1: Create Base Infrastructure
1. Create `Indicators::Base` interface
2. Create `Indicators::Registry` singleton
3. Create individual indicator classes (RSI, MACD, ADX, Supertrend, PriceAction)
4. Create `Indicators::Composite` class

### Phase 2: Refactor Existing Indicators
1. Extract RSI logic from `TrendScorer` → `Indicators::Rsi`
2. Extract MACD logic from `TrendScorer` → `Indicators::Macd`
3. Extract ADX logic from `TrendScorer` → `Indicators::Adx`
4. Wrap existing `Indicators::Supertrend` → `Indicators::SupertrendIndicator`
5. Extract price action logic → `Indicators::PriceAction`

### Phase 3: Update Configuration
1. Add indicator configuration to `algo.yml`
2. Update `AlgoConfig` to load indicator configs
3. Add per-index indicator overrides

### Phase 4: Refactor Signal Generation
1. Update `TrendScorer.ind_score()` to use registry
2. Update `TrendScorer.mtf_score()` to use registry
3. Update `Engine.analyze_timeframe()` to use registry
4. Add indicator result logging

### Phase 5: Testing & Validation
1. Unit tests for each indicator
2. Integration tests for composite indicators
3. Backtest with different indicator combinations
4. Performance testing

---

## Benefits of Modular Architecture

### 1. **Flexibility**
- Enable/disable indicators via config (no code changes)
- Adjust indicator weights/parameters per index
- Test different indicator combinations easily

### 2. **Extensibility**
- Add new indicators by creating a class and registering it
- No need to modify core signal generation code
- Easy to A/B test new indicators

### 3. **Maintainability**
- Clear separation of concerns
- Each indicator is self-contained
- Easier to debug individual indicators

### 4. **Observability**
- Log individual indicator results
- Track which indicators contributed to signal
- Monitor indicator performance over time

### 5. **Configuration-Driven**
- Change indicator behavior without code deployment
- Per-index customization
- Easy rollback if indicator performs poorly

---

## Example Usage

### Enable Only RSI and ADX:

```yaml
signals:
  indicators:
    enabled_indicators:
      - rsi
      - adx
    rsi:
      enabled: true
      weight: 0.5
    adx:
      enabled: true
      weight: 0.5
```

### Use Majority Vote Instead of Weighted Sum:

```yaml
signals:
  indicators:
    composite:
      mode: majority_vote
      require_min_indicators: 3
```

### Per-Index Indicator Override:

```yaml
indices:
  - key: NIFTY
    indicators:
      enabled_indicators:
        - rsi
        - adx
        - supertrend
      rsi:
        period: 21  # Use longer period for NIFTY
```

---

## Migration Path

1. **Backward Compatibility**: Keep existing `TrendScorer` logic as fallback
2. **Feature Flag**: Add `enable_modular_indicators` feature flag
3. **Gradual Migration**: Migrate one indicator at a time
4. **A/B Testing**: Run both systems in parallel and compare results
5. **Full Migration**: Once validated, remove legacy code

---

## Next Steps

1. Review and approve this architecture
2. Create detailed implementation tickets
3. Start with Phase 1 (Base Infrastructure)
4. Test with paper trading
5. Gradually migrate production signals

---

## Notes

- Current `Indicators::Calculator` can be refactored to use the registry
- `Indicators::Supertrend` service already exists and can be wrapped
- `Trading::Indicators` module has some indicator logic that can be migrated
- Consider caching indicator calculations for performance
- Add metrics/telemetry for indicator performance tracking






