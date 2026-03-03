# Configuration Summary

## ✅ Complete: All Values from algo.yml (ENV Fallback)

All configuration values are now properly sourced from `config/algo.yml` with ENV variables as fallback. Only **CLIENT_ID** and **ACCESS_TOKEN** are ENV variables for security.

## Configuration Priority

```
1. algo.yml (Primary) → Preferred source
2. ENV variables (Fallback) → For testing/overrides
3. Default values (Last resort) → Hardcoded defaults
```

## Paper/Live Mode

**Configuration:** `config/algo.yml`
```yaml
paper_trading:
  enabled: true  # true = paper trading, false = live trading
  balance: 100000
```

**Code:** `config/initializers/orders_gateway.rb`
- ✅ Reads from `AlgoConfig.fetch.dig(:paper_trading, :enabled)`
- ✅ No ENV variable needed
- ✅ No hardcoded values

## Indicator Thresholds

**Configuration:** `config/algo.yml`
```yaml
signals:
  indicator_preset: moderate  # loose, moderate, tight, production
  confirmation_mode: all
  min_confidence: 60
```

**ENV Fallback:** `ENV['INDICATOR_PRESET']` (for testing only)

## Risk Management

**Configuration:** `config/algo.yml`
```yaml
risk:
  sl_pct: 0.30
  tp_pct: 0.60
  daily_limits:
    per_index:
      NIFTY: 0.02
```

**ENV Fallback:** `ENV['ALLOC_PCT']`, `ENV['RISK_PER_TRADE_PCT']`, `ENV['DAILY_MAX_LOSS_PCT']` (for testing only)

## Watchlist

**Configuration:** `config/algo.yml`
```yaml
watchlist: []  # Array of "SEGMENT:SECURITY_ID" strings
```

**ENV Fallback:** `ENV['DHANHQ_WS_WATCHLIST']` (for testing only)

## ENV Variables (Security Only)

### Required (Security)
- ✅ `CLIENT_ID` / `DHAN_CLIENT_ID` - API credentials
- ✅ `ACCESS_TOKEN` / `DHAN_ACCESS_TOKEN` - API credentials

### Infrastructure (Acceptable)
- `REDIS_URL` - Infrastructure
- `RAILS_ENV` - Rails environment
- `RAILS_MASTER_KEY` - Encrypted credentials
- `BACKTEST_MODE` - Runtime flag
- `SCRIPT_MODE` - Runtime flag
- `DISABLE_TRADING_SERVICES` - Runtime flag

## Files Modified

1. ✅ `app/services/signal/engine.rb` - Prefers algo.yml for indicator_preset
2. ✅ `app/services/indicators/threshold_config.rb` - Prefers algo.yml over ENV
3. ✅ `app/services/capital/allocator.rb` - Prefers algo.yml for risk values
4. ✅ `app/services/live/market_feed_hub.rb` - Prefers algo.yml for watchlist
5. ✅ `config/algo.yml` - Added watchlist configuration
6. ✅ `config/initializers/orders_gateway.rb` - Uses algo.yml for paper/live mode

## Status: ✅ COMPLETE

All configuration values are properly sourced from `algo.yml` with ENV fallbacks. Only CLIENT_ID and ACCESS_TOKEN are ENV variables.
