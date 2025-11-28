# Testing Volatility Regime Parameters

## Test Coverage

Comprehensive RSpec tests have been added for the volatility regime-based parameter system:

### 1. `spec/services/risk/volatility_regime_service_spec.rb`

Tests for `Risk::VolatilityRegimeService`:

- **VIX Value Classification**: Tests for high (>20), medium (15-20), and low (<15) volatility regimes
- **VIX Instrument Fetching**: Tests fetching VIX from instrument, Redis cache, and API fallbacks
- **ATR Proxy Fallback**: Tests ATR-based volatility proxy when VIX unavailable
- **Custom Thresholds**: Tests custom VIX thresholds from config
- **Error Handling**: Tests graceful error handling and default fallbacks

**Key Test Cases:**
- Returns correct regime for given VIX values
- Falls back through multiple data sources (TickCache → RedisTickCache → API)
- Uses ATR proxy when VIX instrument not found
- Handles exceptions gracefully

### 2. `spec/services/risk/market_condition_service_spec.rb`

Tests for `Risk::MarketConditionService`:

- **Bullish Detection**: Tests detection when trend_score >= 14 and ADX >= 20
- **Bearish Detection**: Tests detection when trend_score <= 7 and ADX >= 20
- **Neutral Detection**: Tests neutral when trend is weak or ADX < 20
- **Index Support**: Tests with NIFTY, BANKNIFTY, and SENSEX
- **Error Handling**: Tests fallbacks when instrument or calculations fail

**Key Test Cases:**
- Correctly identifies bullish/bearish/neutral conditions
- Requires minimum ADX for strong directional bias
- Handles missing instruments and calculation errors
- Works with different index configurations

### 3. `spec/services/risk/regime_parameter_resolver_spec.rb`

Tests for `Risk::RegimeParameterResolver`:

- **Parameter Resolution**: Tests resolving parameters for all regime × condition combinations
- **Auto-Detection**: Tests automatic regime and condition detection
- **Index-Specific**: Tests parameters for NIFTY, BANKNIFTY, and SENSEX
- **Helper Methods**: Tests `sl_pct`, `tp_pct`, `trail_pct`, `timeout_minutes` and their random variants
- **Fallback Behavior**: Tests fallback to default config when regime params unavailable

**Key Test Cases:**
- Resolves correct parameters for high/medium/low volatility
- Resolves correct parameters for bullish/bearish conditions
- Returns midpoint values for helper methods
- Returns random values within ranges
- Falls back gracefully when config unavailable

### 4. `spec/services/live/risk_manager_regime_parameters_spec.rb`

Tests for `Live::RiskManagerService` integration:

- **Parameter Resolution**: Tests `resolve_parameters_for_tracker` method
- **Index Extraction**: Tests `extract_index_from_instrument` method
- **Hard Limits Enforcement**: Tests `enforce_hard_limits` with regime-based parameters
- **Fallback Behavior**: Tests fallback to default parameters when regime params unavailable
- **Different Regimes**: Tests behavior with high/medium/low volatility regimes
- **Different Conditions**: Tests behavior with bullish/bearish conditions

**Key Test Cases:**
- Uses regime-based SL/TP when enabled
- Extracts index from tracker meta or instrument symbol
- Falls back to defaults when regime params unavailable
- Applies correct parameters for each regime × condition combination
- Exits positions with regime-based reasons

## Running Tests

### Run All Regime Tests
```bash
bundle exec rspec spec/services/risk/
```

### Run Specific Test Files
```bash
# Volatility regime service
bundle exec rspec spec/services/risk/volatility_regime_service_spec.rb

# Market condition service
bundle exec rspec spec/services/risk/market_condition_service_spec.rb

# Parameter resolver
bundle exec rspec spec/services/risk/regime_parameter_resolver_spec.rb

# Risk manager integration
bundle exec rspec spec/services/live/risk_manager_regime_parameters_spec.rb
```

### Run with Coverage
```bash
COVERAGE=true bundle exec rspec spec/services/risk/
```

## Test Patterns Used

### Mocking External Dependencies
- `AlgoConfig.fetch` - Mocked to return test configuration
- `IndexInstrumentCache.instance` - Mocked to return test instruments
- `Risk::VolatilityRegimeService` - Mocked in resolver tests
- `Risk::MarketConditionService` - Mocked in resolver tests
- `Risk::RegimeParameterResolver` - Mocked in risk manager tests

### Factory Usage
- `create(:instrument)` - Creates test instruments
- `create(:position_tracker)` - Creates test position trackers
- `build(:candle_series, :with_candles)` - Creates test candle series

### Test Structure
- `describe` blocks for major functionality
- `context` blocks for different scenarios
- `before` blocks for test setup
- `it` blocks for individual test cases

## Test Coverage Statistics

- **VolatilityRegimeService**: ~15 test cases covering all code paths
- **MarketConditionService**: ~12 test cases covering all conditions
- **RegimeParameterResolver**: ~20 test cases covering all combinations
- **RiskManager Integration**: ~15 test cases covering integration scenarios

**Total**: ~62 test cases providing comprehensive coverage

## Future Test Additions

Consider adding:

1. **Integration Tests**: End-to-end tests with real VIX data
2. **Performance Tests**: Test parameter resolution performance
3. **Edge Cases**: Test boundary conditions (exact thresholds, nil values)
4. **Concurrency Tests**: Test thread safety of parameter resolution
5. **Regression Tests**: Test against historical market data
