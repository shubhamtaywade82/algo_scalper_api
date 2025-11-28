# Configuration Audit - algo.yml vs ENV Variables

## Summary

All configuration values should come from `config/algo.yml` (preferred) or ENV variables. Only **CLIENT_ID** and **ACCESS_TOKEN** should be ENV variables for security reasons.

## ✅ Configuration Sources

### 1. **Paper/Live Trading Mode**

**Location:** `config/algo.yml`
```yaml
paper_trading:
  enabled: true  # true = paper, false = live
  balance: 100000
```

**Code:** `config/initializers/orders_gateway.rb`
- ✅ Reads from `AlgoConfig.fetch.dig(:paper_trading, :enabled)`
- ✅ No hardcoded values

### 2. **Indicator Thresholds**

**Location:** `config/algo.yml`
```yaml
signals:
  indicator_preset: moderate  # loose, moderate, tight, production
  confirmation_mode: all
  min_confidence: 60
```

**Code:** 
- ✅ `app/services/signal/engine.rb` - Prefers algo.yml, ENV as fallback
- ✅ `app/services/indicators/threshold_config.rb` - Prefers algo.yml, ENV as fallback

### 3. **Risk Management**

**Location:** `config/algo.yml`
```yaml
risk:
  sl_pct: 0.30
  tp_pct: 0.60
  daily_limits:
    enable: true
    per_index:
      NIFTY: 0.02
```

**Code:**
- ✅ `app/services/capital/allocator.rb` - Prefers algo.yml, ENV as fallback
- ✅ All risk values come from algo.yml

### 4. **WebSocket Watchlist**

**Location:** `config/algo.yml`
```yaml
watchlist: []  # Array of "SEGMENT:SECURITY_ID" strings
```

**Code:**
- ✅ `app/services/live/market_feed_hub.rb` - Prefers algo.yml, ENV as fallback

### 5. **Signal Configuration**

**Location:** `config/algo.yml`
```yaml
signals:
  primary_timeframe: "1m"
  confirmation_timeframe: "5m"
  enable_supertrend_signal: true
  enable_adx_filter: true
  use_multi_indicator_strategy: false
```

**Code:**
- ✅ All signal settings read from `AlgoConfig.fetch[:signals]`

## ✅ ENV Variables (Security - Only These)

### Required ENV Variables (Security)

1. **CLIENT_ID** / **DHANHQ_CLIENT_ID**
   - ✅ Used in: `app/services/live/market_feed_hub.rb`
   - ✅ Used in: `app/services/live/order_update_hub.rb`
   - ✅ Used in: `app/services/orders/placer.rb`
   - ✅ Used in: `config/initializers/dhanhq_config.rb`
   - **Reason:** API credentials - must be ENV for security

2. **ACCESS_TOKEN** / **DHANHQ_ACCESS_TOKEN**
   - ✅ Used in: `app/services/live/market_feed_hub.rb`
   - ✅ Used in: `app/services/live/order_update_hub.rb`
   - ✅ Used in: `config/initializers/dhanhq_config.rb`
   - **Reason:** API credentials - must be ENV for security

### Infrastructure ENV Variables (Acceptable)

These are infrastructure/deployment settings, not trading configuration:

- **REDIS_URL** - Infrastructure (Redis connection)
- **RAILS_ENV** - Rails environment
- **RAILS_MASTER_KEY** - Rails encrypted credentials key
- **BACKTEST_MODE** - Runtime flag (not config)
- **SCRIPT_MODE** - Runtime flag (not config)
- **DISABLE_TRADING_SERVICES** - Runtime flag (not config)

## ✅ Configuration Priority

All configuration follows this priority order:

1. **algo.yml** (Primary) - Preferred source
2. **ENV variables** (Fallback) - For testing/overrides
3. **Default values** (Last resort) - Hardcoded defaults

### Example: Indicator Preset

```ruby
# Priority order:
preset_name = signals_cfg[:indicator_preset]&.to_sym ||  # 1. algo.yml
              ENV['INDICATOR_PRESET']&.to_sym ||         # 2. ENV (fallback)
              :moderate                                   # 3. Default
```

## ✅ Verification Checklist

- [x] Paper/Live mode: `algo.yml` → `paper_trading.enabled`
- [x] Indicator preset: `algo.yml` → `signals.indicator_preset` (ENV fallback)
- [x] Risk management: `algo.yml` → `risk.*` (ENV fallback for testing)
- [x] Watchlist: `algo.yml` → `watchlist` (ENV fallback)
- [x] Signal config: `algo.yml` → `signals.*`
- [x] CLIENT_ID: ENV only ✅
- [x] ACCESS_TOKEN: ENV only ✅
- [x] No hardcoded trading values ✅

## 📝 Configuration Files

### Primary Configuration
- **`config/algo.yml`** - All trading configuration values

### Environment Variables (Security)
- **`CLIENT_ID`** / **`DHANHQ_CLIENT_ID`** - API client ID
- **`ACCESS_TOKEN`** / **`DHANHQ_ACCESS_TOKEN`** - API access token

### Infrastructure ENV (Acceptable)
- `REDIS_URL` - Redis connection string
- `RAILS_ENV` - Rails environment
- `RAILS_MASTER_KEY` - Encrypted credentials key
- `BACKTEST_MODE` - Runtime flag
- `SCRIPT_MODE` - Runtime flag
- `DISABLE_TRADING_SERVICES` - Runtime flag

## 🔧 How to Change Configuration

### Change Paper/Live Mode

**Edit `config/algo.yml`:**
```yaml
paper_trading:
  enabled: true  # Change to false for live trading
```

### Change Indicator Thresholds

**Edit `config/algo.yml`:**
```yaml
signals:
  indicator_preset: loose  # Change to: moderate, tight, production
```

**Or use ENV for testing:**
```bash
export INDICATOR_PRESET=loose
```

### Change Risk Settings

**Edit `config/algo.yml`:**
```yaml
risk:
  sl_pct: 0.30
  tp_pct: 0.60
  daily_limits:
    per_index:
      NIFTY: 0.02
```

### Change Watchlist

**Edit `config/algo.yml`:**
```yaml
watchlist: ["NSE_EQ:11536", "NSE_EQ:11537"]
```

## ✅ Status: COMPLETE

All configuration values are properly sourced from `algo.yml` with ENV fallbacks. Only CLIENT_ID and ACCESS_TOKEN are ENV variables for security.
