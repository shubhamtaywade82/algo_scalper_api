# Technical Analysis Agent - Tools & Services Analysis

## Current Agent Tools (11)

The agent currently has access to these 11 tools:

### Market Data Tools
1. **`get_index_ltp`** - Get LTP for indices (NIFTY, BANKNIFTY, SENSEX)
2. **`get_instrument_ltp`** - Get LTP for specific instruments
3. **`get_ohlc`** - Get OHLC data for instruments
4. **`get_historical_data`** - Get historical candle data

### Technical Analysis Tools
5. **`calculate_indicator`** - Calculate basic technical indicators (RSI, MACD, ADX, Supertrend, ATR)
6. **`calculate_advanced_indicator`** - Calculate advanced indicators (HolyGrail, TrendDuration)
7. **`analyze_option_chain`** - Analyze option chains for bullish/bearish candidates

### Trading & Position Tools
8. **`get_trading_stats`** - Get trading statistics (win rate, PnL)
9. **`get_active_positions`** - Get currently active positions

### Backtesting & Optimization Tools
10. **`run_backtest`** - Run backtests on historical data with No-Trade Engine
11. **`optimize_indicator`** - Optimize indicator parameters using historical data

## Available Services NOT Currently Exposed

### Signal Generation Services
- **`Signal::Engine`** - Generate trading signals with comprehensive validation
- **`Signal::Scheduler`** - Signal scheduling and processing
- **`Signal::TrendScorer`** - Trend scoring (0-21 score)
- **`Signal::StateTracker`** - Track signal state and persistence

### Entry & Validation Services
- **`Entries::EntryGuard`** - Entry validation and duplicate prevention
- **`Entries::NoTradeEngine`** - No-trade validation engine
- **`Entries::NoTradeContextBuilder`** - Build no-trade context

### Capital & Risk Management
- **`Capital::Allocator`** - Position sizing and capital allocation
- **`Capital::DynamicRiskAllocator`** - Dynamic risk-based allocation
- **`Live::RiskManagerService`** - Risk management and exit enforcement
- **`Live::DailyLimits`** - Daily loss/profit/trade limits tracking
- **`Live::TrailingEngine`** - Trailing stop management
- **`Live::UnderlyingMonitor`** - Underlying price monitoring

### Additional Indicators
- **`Indicators::HolyGrail`** - Holy Grail indicator
- **`Indicators::Calculator`** - Comprehensive indicator calculator
- **`Indicators::TrendDurationIndicator`** - Trend duration analysis

### Trading Session & Market Status
- **`TradingSession::Service`** - Trading session checks (entry allowed, market closed, etc.)
- **`Live::FeedHealthService`** - Market feed health monitoring
- **`Live::MarketFeedHub`** - Market feed status

### Position & Order Management
- **`PositionTracker`** - Model with extensive methods for position analysis
- **`Live::PositionSyncService`** - Position synchronization
- **`Live::RedisPnlCache`** - Real-time PnL cache
- **`Orders::Manager`** - Order management

### Option Chain Analysis
- **`Options::ChainAnalyzer`** - Alternative chain analyzer
- **`Options::StrikeSelector`** - Strike selection logic
- **`Options::PremiumFilter`** - Premium filtering

### Backtesting & Optimization
- **`BacktestService`** - Backtesting capabilities
- **`Optimization::IndicatorOptimizer`** - Indicator optimization
- **`Optimization::StrategyBacktester`** - Strategy backtesting

## Recommended Additional Tools

### High Priority (Most Useful)

1. **`check_trading_session`** - Check if trading is allowed, market status
2. **`get_daily_limits`** - Get daily loss/profit/trade counts
3. **`calculate_position_size`** - Calculate position size for a given risk
4. **`validate_entry`** - Validate if an entry would be allowed
5. **`get_signal_status`** - Get current signal status for an index
6. **`get_underlying_trend`** - Get underlying trend analysis

### Medium Priority

7. **`get_feed_health`** - Check market feed health
8. **`get_trailing_stop_info`** - Get trailing stop information for positions
9. **`analyze_entry_path`** - Analyze entry path and strategy
10. **`get_capital_allocation`** - Get capital allocation details

### Low Priority (Advanced)

11. **`run_backtest`** - Run backtest analysis
12. **`optimize_indicator`** - Optimize indicator parameters
13. **`get_risk_metrics`** - Get comprehensive risk metrics

## Implementation Notes

To add new tools:

1. Add tool definition to `build_tools_registry` in `technical_analysis_agent.rb`
2. Implement `tool_<name>` method
3. Update system prompt with tool description
4. Add examples to `ai:examples` rake task

## Current Coverage

**Coverage: ~30%** of available services are exposed as tools (up from 20%).

The agent has good coverage for:
- ✅ Market data (LTP, OHLC, historical)
- ✅ Technical indicators (basic + advanced: HolyGrail, TrendDuration)
- ✅ Option chain analysis
- ✅ Trading statistics
- ✅ Backtesting capabilities
- ✅ Indicator optimization

The agent is missing (intentionally - these are for scalping automation):
- ❌ Signal generation capabilities (scalping automation)
- ❌ Entry validation (scalping automation)
- ❌ Risk management tools (scalping automation)
- ❌ Capital allocation (scalping automation)
- ❌ Trading session checks (scalping automation)
