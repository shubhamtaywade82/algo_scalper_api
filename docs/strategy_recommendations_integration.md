# Strategy Recommendations Integration Guide

## Overview

The StrategyRecommender service has been integrated into the Signal::Engine flow, allowing the system to automatically use the best-performing strategies based on comprehensive backtest results.

## How It Works

### 1. **StrategyRecommender Service**
   - Contains backtest results for all index/timeframe/strategy combinations
   - Provides recommendations based on expectancy, win rate, and trade count
   - Located at: `app/services/strategy_recommender.rb`

### 2. **Signal::Engine Integration**
   - Checks `use_strategy_recommendations` flag in `config/algo.yml`
   - If enabled, queries StrategyRecommender for best strategy per index
   - Falls back to traditional Supertrend+ADX if recommendations unavailable
   - Located at: `app/services/signal/engine.rb`

### 3. **StrategyAdapter**
   - Converts strategy signals to Signal::Engine format
   - Handles different strategy types (SimpleMomentumStrategy, InsideBarStrategy, SupertrendAdxStrategy)
   - Located at: `app/services/signal/strategy_adapter.rb`

## Configuration

### Enable Strategy Recommendations

Edit `config/algo.yml`:

```yaml
signals:
  use_strategy_recommendations: true  # Enable backtest-based strategy selection
  primary_timeframe: "1m"             # Base timeframe (will be overridden by recommended strategy's timeframe)
```

**Important:** When `use_strategy_recommendations: true`, the system automatically uses the recommended strategy's timeframe (5min or 15min) instead of the `primary_timeframe` config. The config value is only used as a fallback if no recommendation is found.

### Timeframe Handling

- **When enabled**: System fetches OHLC data at the recommended strategy's timeframe (e.g., 5min for SimpleMomentumStrategy on BANKNIFTY)
- **When disabled**: System uses `primary_timeframe` from config (default: 1m)
- **Scheduler frequency**: Runs every 30 seconds (checks for new candles regardless of timeframe)

### Current Recommendations (from backtest results)

Based on 90-day backtests:

- **NIFTY @ 5min**: SimpleMomentumStrategy (52.63% win rate, +0.02% expectancy)
- **BANKNIFTY @ 5min**: SimpleMomentumStrategy (55.77% win rate, +0.04% expectancy)
- **SENSEX @ 5min**: SupertrendAdxStrategy (52.54% win rate, +0.03% expectancy)

## Usage

### Automatic (Recommended)

1. Set `use_strategy_recommendations: true` in `config/algo.yml`
2. Restart the application
3. Signal::Engine will automatically use recommended strategies per index

### Manual Query

```ruby
# In Rails console
rec = StrategyRecommender.recommend(symbol: 'BANKNIFTY', interval: '5')
# => { strategy_class: SimpleMomentumStrategy, expectancy: 0.04, ... }

# Get best for an index
best = StrategyRecommender.best_for_index(symbol: 'NIFTY')
# => Best strategy recommendation

# Get live trading config
config = StrategyRecommender.live_trading_config
# => Hash with recommendations for all indices
```

## Flow Diagram

```
Signal::Scheduler.start!
  ↓
Signal::Engine.run_for(index_cfg)
  ↓
Check: use_strategy_recommendations enabled?
  ├─ YES → StrategyRecommender.recommend(symbol, interval)
  │         ↓
  │         StrategyAdapter.analyze_with_strategy()
  │         ↓
  │         Generate signal using recommended strategy
  │
  └─ NO → Traditional Supertrend + ADX analysis
            ↓
            Generate signal using Supertrend/ADX
```

## Updating Recommendations

After running new backtests, update `StrategyRecommender::BACKTEST_RESULTS`:

1. Run comprehensive backtest: `rails "backtest:all_indices[90]"`
2. Update `app/services/strategy_recommender.rb` with new results
3. Restart application to use updated recommendations

## Fallback Behavior

- If `use_strategy_recommendations: false` → Uses traditional Supertrend+ADX
- If recommendation not found → Falls back to Supertrend+ADX
- If strategy fails → Logs error and skips signal generation

## Monitoring

Check logs for strategy selection:

```
[Signal] Using recommended strategy for BANKNIFTY: SimpleMomentumStrategy (5min) - Expectancy: 0.04%
```

## Notes

- Strategy recommendations are based on historical backtest data
- Market conditions may change, affecting strategy performance
- Regularly update backtest results (monthly recommended)
- Monitor live performance vs. backtest expectations
- Start with small position sizes when enabling new strategies

