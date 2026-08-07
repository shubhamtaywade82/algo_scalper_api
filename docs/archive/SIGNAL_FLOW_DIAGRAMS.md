# Signal Generation Flow Diagrams

## Current Architecture Flow

### Signal::Scheduler Flow (Primary Path)

```
Signal::Scheduler.start()
  │
  ├─> Loop every 30 seconds
  │   │
  │   ├─> process_index(index_cfg)
  │   │   │
  │   │   ├─> evaluate_supertrend_signal(index_cfg)
  │   │   │   │
  │   │   │   ├─> IF trend_scorer_enabled?
  │   │   │   │   │
  │   │   │   │   ├─> Signal::TrendScorer.compute_direction()
  │   │   │   │   │   │
  │   │   │   │   │   ├─> compute_trend_score()
  │   │   │   │   │   │   │
  │   │   │   │   │   │   ├─> pa_score(series)          [HARDCODED]
  │   │   │   │   │   │   │   ├─> Momentum calculation
  │   │   │   │   │   │   │   ├─> Structure breaks
  │   │   │   │   │   │   │   ├─> Candle patterns
  │   │   │   │   │   │   │   └─> Trend consistency
  │   │   │   │   │   │   │
  │   │   │   │   │   │   ├─> ind_score(series)          [HARDCODED]
  │   │   │   │   │   │   │   ├─> RSI (period: 14)       [HARDCODED]
  │   │   │   │   │   │   │   ├─> MACD (12, 26, 9)       [HARDCODED]
  │   │   │   │   │   │   │   ├─> ADX (period: 14)       [HARDCODED]
  │   │   │   │   │   │   │   └─> Supertrend (10, 2.0)   [HARDCODED]
  │   │   │   │   │   │   │
  │   │   │   │   │   │   └─> mtf_score(primary, conf)   [HARDCODED]
  │   │   │   │   │   │       ├─> RSI alignment
  │   │   │   │   │   │       ├─> Supertrend alignment
  │   │   │   │   │   │       └─> Price alignment
  │   │   │   │   │   │
  │   │   │   │   │   └─> Return direction if score >= threshold
  │   │   │   │   │
  │   │   │   │   └─> ELSE (Legacy Path)
  │   │   │   │       │
  │   │   │   │       └─> Signal::Engine.analyze_multi_timeframe()
  │   │   │   │           │
  │   │   │   │           ├─> analyze_timeframe(primary)
  │   │   │   │           │   ├─> Supertrend calculation    [CONFIGURABLE]
  │   │   │   │           │   ├─> ADX calculation          [CONFIGURABLE]
  │   │   │   │           │   └─> decide_direction()
  │   │   │   │           │
  │   │   │   │           └─> analyze_timeframe(confirmation)
  │   │   │   │               └─> multi_timeframe_direction()
  │   │   │   │
  │   │   │   └─> select_candidate_from_chain()
  │   │   │
  │   │   └─> process_signal(index_cfg, signal)
  │   │       └─> Entries::EntryGuard.try_enter()
```

### Signal::Engine Flow (Alternative Path)

```
Signal::Engine.run_for(index_cfg)
  │
  ├─> IF use_strategy_recommendations?
  │   │
  │   └─> analyze_with_recommended_strategy()
  │       └─> StrategyAdapter.analyze_with_strategy()
  │
  ├─> ELSE IF enable_supertrend_signal?
  │   │
  │   └─> analyze_timeframe()
  │       ├─> Supertrend calculation
  │       ├─> ADX calculation
  │       └─> decide_direction()
  │
  ├─> IF enable_confirmation_timeframe?
  │   │
  │   └─> analyze_timeframe(confirmation)
  │       └─> multi_timeframe_direction()
  │
  ├─> comprehensive_validation()
  │   ├─> validate_iv_rank()          [OPTIONAL]
  │   ├─> validate_theta_risk()       [OPTIONAL]
  │   ├─> validate_adx_strength()     [IF enable_adx_filter]
  │   ├─> validate_trend_confirmation() [OPTIONAL]
  │   └─> validate_market_timing()    [ALWAYS]
  │
  ├─> calculate_confidence_score()
  │
  ├─> TradingSignal.create_from_analysis()
  │
  └─> Options::ChainAnalyzer.pick_strikes()
      └─> Entries::EntryGuard.try_enter()
```

---

## Proposed Modular Architecture Flow

### Indicator Registry Flow

```
Indicators::Registry (Singleton)
  │
  ├─> register(name, indicator_class, config)
  │   └─> Store in @indicators hash
  │
  ├─> enable(name) / disable(name)
  │   └─> Update @enabled_indicators array
  │
  ├─> create(name, series:, config:)
  │   └─> Instantiate indicator class
  │
  └─> calculate_all(series, config_overrides:)
      │
      ├─> For each enabled indicator:
      │   │
      │   ├─> Create indicator instance
      │   ├─> Check if ready? (enough data)
      │   ├─> Calculate indicator value
      │   ├─> Get signal_direction
      │   ├─> Get confidence_score
      │   └─> Return result hash
      │
      └─> Return array of indicator results
```

### Composite Indicator Flow

```
Indicators::Composite
  │
  ├─> initialize(series:, indicators:, mode:, config:)
  │   └─> Store indicator results array
  │
  ├─> signal_direction
  │   │
  │   ├─> IF mode == :weighted_sum
  │   │   └─> calculate_weighted_sum_direction()
  │   │       ├─> Sum bullish scores (weight * confidence)
  │   │       ├─> Sum bearish scores (weight * confidence)
  │   │       └─> Return direction with highest score
  │   │
  │   ├─> IF mode == :majority_vote
  │   │   └─> calculate_majority_vote_direction()
  │   │       ├─> Count bullish votes
  │   │       ├─> Count bearish votes
  │   │       └─> Return majority direction
  │   │
  │   ├─> IF mode == :all_must_agree
  │   │   └─> calculate_all_must_agree_direction()
  │   │       └─> Return direction only if all agree
  │   │
  │   └─> IF mode == :any_one
  │       └─> calculate_any_one_direction()
  │           └─> Return direction if any indicator signals
  │
  └─> confidence_score
      └─> Calculate based on mode
```

### Refactored TrendScorer Flow

```
Signal::TrendScorer.ind_score(series)
  │
  ├─> Get indicator config from AlgoConfig
  │   └─> signals.indicators.enabled_indicators
  │
  ├─> Indicators::Registry.instance.calculate_all(series)
  │   │
  │   ├─> For each enabled indicator:
  │   │   ├─> RSI → Indicators::Rsi.new(...)
  │   │   ├─> MACD → Indicators::Macd.new(...)
  │   │   ├─> ADX → Indicators::Adx.new(...)
  │   │   ├─> Supertrend → Indicators::SupertrendIndicator.new(...)
  │   │   └─> PriceAction → Indicators::PriceAction.new(...)
  │   │
  │   └─> Return array of results
  │
  ├─> Filter to only enabled indicators
  │
  ├─> Indicators::Composite.new(
  │       indicators: results,
  │       mode: config[:composite][:mode],
  │       config: config[:composite]
  │     )
  │
  └─> Convert composite.confidence_score (0-1) to score (0-7)
```

### Refactored Signal Generation Flow

```
Signal::Scheduler.evaluate_supertrend_signal()
  │
  ├─> IF trend_scorer_enabled?
  │   │
  │   └─> Signal::TrendScorer.compute_direction()
  │       │
  │       ├─> compute_trend_score()
  │       │   │
  │       │   ├─> pa_score() → Uses Indicators::PriceAction
  │       │   │
  │       │   ├─> ind_score() → Uses Indicators::Registry + Composite
  │       │   │   │
  │       │   │   ├─> Registry.calculate_all()
  │       │   │   │   ├─> RSI calculation
  │       │   │   │   ├─> MACD calculation
  │       │   │   │   ├─> ADX calculation
  │       │   │   │   ├─> Supertrend calculation
  │       │   │   │   └─> PriceAction calculation
  │       │   │   │
  │       │   │   └─> Composite.combine()
  │       │   │
  │       │   └─> mtf_score() → Uses Indicators::Registry for both timeframes
  │       │
  │       └─> Return direction if score >= threshold
  │
  └─> ELSE
      └─> Signal::Engine.analyze_multi_timeframe()
          └─> Uses Indicators::Registry for Supertrend + ADX
```

---

## Indicator Class Structure

### Base Indicator Interface

```
Indicators::Base (Abstract)
  │
  ├─> initialize(series:, config:)
  │   └─> Store series and config
  │
  ├─> calculate() → Abstract
  │   └─> Must be implemented by subclass
  │
  ├─> signal_direction() → Abstract
  │   └─> Returns: :bullish, :bearish, :neutral, :avoid
  │
  ├─> confidence_score() → Abstract
  │   └─> Returns: 0.0 to 1.0
  │
  ├─> value() → Abstract
  │   └─> Returns: Raw indicator value
  │
  └─> ready?() → Abstract
      └─> Returns: true if enough data available
```

### Example: RSI Indicator

```
Indicators::Rsi < Indicators::Base
  │
  ├─> initialize(series:, config:)
  │   └─> @period = config[:period] || 14
  │
  ├─> calculate()
  │   └─> Use CandleSeries.rsi(@period)
  │
  ├─> signal_direction()
  │   ├─> IF rsi > 50 && rsi < 70 → :bullish
  │   ├─> IF rsi < 50 && rsi > 30 → :bearish
  │   └─> ELSE → :neutral
  │
  ├─> confidence_score()
  │   ├─> IF rsi in strong range → 0.8-1.0
  │   ├─> IF rsi in moderate range → 0.5-0.8
  │   └─> ELSE → 0.0-0.5
  │
  ├─> value()
  │   └─> Return calculated RSI value
  │
  └─> ready?()
      └─> series.candles.size >= @period + 1
```

---

## Configuration Flow

### Config Loading Flow

```
Rails Application Start
  │
  ├─> config/initializers/algo_config.rb
  │   │
  │   └─> YAML.load_file('config/algo.yml')
  │       │
  │       └─> Store in Rails.application.config.x.algo
  │
  ├─> Indicators::Registry.instance.initialize()
  │   │
  │   ├─> Load indicator configs from algo.yml
  │   │   └─> signals.indicators.*
  │   │
  │   ├─> Register all indicator classes
  │   │   ├─> register(:rsi, Indicators::Rsi, config[:rsi])
  │   │   ├─> register(:macd, Indicators::Macd, config[:macd])
  │   │   ├─> register(:adx, Indicators::Adx, config[:adx])
  │   │   ├─> register(:supertrend, Indicators::SupertrendIndicator, config[:supertrend])
  │   │   └─> register(:price_action, Indicators::PriceAction, config[:price_action])
  │   │
  │   └─> Enable indicators from config
  │       └─> config[:enabled_indicators].each { |name| enable(name) }
```

### Runtime Configuration Override

```
Per-Index Indicator Override
  │
  ├─> Signal::TrendScorer.compute_direction(index_cfg:)
  │   │
  │   ├─> Get global indicator config
  │   │   └─> AlgoConfig.fetch[:signals][:indicators]
  │   │
  │   ├─> Get per-index override (if exists)
  │   │   └─> index_cfg[:indicators]
  │   │
  │   ├─> Merge configs (index overrides global)
  │   │
  │   └─> Pass merged config to Registry.calculate_all()
```

---

## Data Flow Diagram

### Current Data Flow

```
CandleSeries
  │
  ├─> TrendScorer.ind_score()
  │   │
  │   ├─> Indicators::Calculator.new(series)
  │   │   │
  │   │   ├─> calculator.rsi(14)        [HARDCODED]
  │   │   ├─> calculator.macd(12,26,9) [HARDCODED]
  │   │   └─> calculator.adx(14)       [HARDCODED]
  │   │
  │   └─> Indicators::Supertrend.new(...) [HARDCODED]
  │
  └─> Manual scoring logic in TrendScorer
      └─> Return 0-7 score
```

### Proposed Data Flow

```
CandleSeries
  │
  ├─> Indicators::Registry.calculate_all(series, config:)
  │   │
  │   ├─> For each enabled indicator:
  │   │   │
  │   │   ├─> Create indicator instance
  │   │   │   └─> Indicators::Rsi.new(series:, config:)
  │   │   │
  │   │   ├─> indicator.calculate()
  │   │   │   └─> Returns raw value
  │   │   │
  │   │   ├─> indicator.signal_direction()
  │   │   │   └─> Returns :bullish/:bearish/:neutral/:avoid
  │   │   │
  │   │   └─> indicator.confidence_score()
  │   │       └─> Returns 0.0-1.0
  │   │
  │   └─> Return array of results
  │
  ├─> Indicators::Composite.new(indicators: results, mode: :weighted_sum)
  │   │
  │   ├─> composite.signal_direction()
  │   │   └─> Combines all indicator directions
  │   │
  │   └─> composite.confidence_score()
  │       └─> Combines all indicator confidences
  │
  └─> TrendScorer.ind_score()
      └─> Convert composite.confidence_score to 0-7 score
```

---

## Comparison: Current vs Proposed

### Current Architecture Issues

```
❌ Hardcoded indicator parameters
❌ No way to disable individual indicators
❌ Scoring logic embedded in TrendScorer
❌ Cannot easily add new indicators
❌ No per-index indicator customization
❌ Mixed responsibilities (calculation + scoring)
```

### Proposed Architecture Benefits

```
✅ Configurable indicator parameters
✅ Enable/disable indicators via config
✅ Separated calculation and scoring
✅ Easy to add new indicators (just register)
✅ Per-index indicator overrides
✅ Clear separation of concerns
✅ Testable individual components
✅ Observable indicator performance
```

---

## Migration Sequence

### Step 1: Create Base Infrastructure
```
1. Create Indicators::Base
2. Create Indicators::Registry
3. Create Indicators::Composite
```

### Step 2: Extract Existing Indicators
```
1. Create Indicators::Rsi (extract from TrendScorer)
2. Create Indicators::Macd (extract from TrendScorer)
3. Create Indicators::Adx (extract from TrendScorer)
4. Create Indicators::SupertrendIndicator (wrap existing)
5. Create Indicators::PriceAction (extract from TrendScorer)
```

### Step 3: Update Configuration
```
1. Add indicator configs to algo.yml
2. Update AlgoConfig loader
3. Add feature flag: enable_modular_indicators
```

### Step 4: Refactor Signal Generation
```
1. Update TrendScorer.ind_score() to use registry
2. Update TrendScorer.mtf_score() to use registry
3. Update Engine.analyze_timeframe() to use registry
```

### Step 5: Testing & Validation
```
1. Unit tests for each indicator
2. Integration tests for composite
3. Backtest comparison
4. Paper trading validation
```






