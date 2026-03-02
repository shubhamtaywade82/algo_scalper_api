# DhanHQ Configuration Review

## Summary

This document reviews the DhanHQ configuration setup and documents all available configuration options.

## Configuration Architecture

### 1. **Initializer** (`config/initializers/dhanhq_config.rb`)

The initializer performs three key functions:

1. **Environment Variable Normalization**: Supports both naming conventions
   - `CLIENT_ID` or `DHAN_CLIENT_ID`
   - `ACCESS_TOKEN` or `DHAN_ACCESS_TOKEN`
   - All gem options support both `DHAN_` and `DHANHQ_` prefixes

2. **Gem Configuration**: Calls `DhanHQ.configure_with_env` which reads from ENV

3. **Rails App Configuration**: Stores app-specific settings in `Rails.application.config.x.dhanhq`

### 2. **Gem Configuration Options**

The DhanHQ gem supports the following environment variables (all with `DHAN_` prefix):

#### Required
- `CLIENT_ID` - Your Dhan trading client ID
- `ACCESS_TOKEN` - REST/WebSocket access token from Dhan APIs

#### Optional
- `DHAN_BASE_URL` - Override REST API host (default: `"https://api.dhan.co/v2"`)
- `DHAN_WS_VERSION` - WebSocket API version (default: `2`)
- `DHAN_WS_ORDER_URL` - Order update WebSocket endpoint (default: `"wss://api-order-update.dhan.co"`)
- `DHAN_WS_MARKET_FEED_URL` - Market feed WebSocket endpoint (default: `"wss://api-feed.dhan.co"`)
- `DHAN_WS_MARKET_DEPTH_URL` - Market depth WebSocket endpoint (default: `"wss://depth-api-feed.dhan.co/twentydepth"`)
- `DHAN_MARKET_DEPTH_LEVEL` - Market depth level (default: `"20"`, can be `20` or `200`)
- `DHAN_WS_USER_TYPE` - WebSocket user type: `"SELF"` or `"PARTNER"` (default: `"SELF"`)
- `DHAN_PARTNER_ID` - Partner ID (required when `DHAN_WS_USER_TYPE=PARTNER`)
- `DHAN_PARTNER_SECRET` - Partner secret (required when `DHAN_WS_USER_TYPE=PARTNER`)
- `DHAN_LOG_LEVEL` - Logger verbosity (`INFO`, `DEBUG`, `WARN`, `ERROR`, `FATAL`)

**Note**: All `DHAN_` prefixed variables can also be set with `DHANHQ_` prefix (e.g., `DHANHQ_BASE_URL`), and the initializer will normalize them.

### 3. **Rails App Configuration** (`Rails.application.config.x.dhanhq`)

These are application-specific settings, not passed to the gem:

- `enabled` - Whether DhanHQ integration is enabled (default: `!Rails.env.test?`)
- `ws_enabled` - Whether WebSocket market feed is enabled (default: `!Rails.env.test?`)
- `order_ws_enabled` - Whether order update WebSocket is enabled (default: `!Rails.env.test?`)
- `enable_order_logging` - Enable actual order placement (default: `ENV["ENABLE_ORDER"] == "true"`)
- `ws_mode` - WebSocket mode (`:quote`, `:ticker`, `:full`) (default: `ENV["DHANHQ_WS_MODE"] || "quote"`)
- `ws_watchlist` - Fallback watchlist from ENV (default: `ENV["DHANHQ_WS_WATCHLIST"]`)
- `order_ws_url` - Stored for reference (not used by gem, gem reads from `DHAN_WS_ORDER_URL`)
- `ws_user_type` - Stored for reference (not used by gem, gem reads from `DHAN_WS_USER_TYPE`)
- `partner_id` - Stored for reference (not used by gem, gem reads from `DHAN_PARTNER_ID`)
- `partner_secret` - Stored for reference (not used by gem, gem reads from `DHAN_PARTNER_SECRET`)

## Accessing Configuration

### In Application Code

**To get client_id for order payloads:**
```ruby
# Preferred: Use gem's configuration
DhanHQ.configuration.client_id

# Fallback: Direct ENV access (supports both naming conventions)
ENV['DHAN_CLIENT_ID'] || ENV['CLIENT_ID']
```

**To check if order placement is enabled:**
```ruby
Rails.application.config.x.dhanhq&.enable_order_logging
# or
ENV["ENABLE_ORDER"] == "true"
```

**To get WebSocket mode:**
```ruby
Rails.application.config.x.dhanhq&.ws_mode
# or
ENV["DHANHQ_WS_MODE"] || "quote"
```

### Direct Gem Configuration Access

```ruby
# Access gem configuration
DhanHQ.configuration.client_id
DhanHQ.configuration.access_token
DhanHQ.configuration.base_url
DhanHQ.configuration.ws_version

# Modify gem configuration (if needed)
DhanHQ.configuration.client_id = "new_client_id"
```

## Bugs Fixed

### 1. **Orders::Placer Bug** (Fixed)

**Issue**: Code was trying to access `Rails.application.config.x.dhanhq&.client_id` which doesn't exist.

**Fix**: Changed to use `DhanHQ.configuration.client_id` with fallback to ENV variables.

**Files Fixed**:
- `app/services/orders/placer.rb` (3 occurrences: `buy_market!`, `sell_market!`, `exit_position!`)

**Before**:
```ruby
dhanClientId: Rails.application.config.x.dhanhq&.client_id || AlgoConfig.fetch.dig(:dhanhq, :client_id)
```

**After**:
```ruby
dhanClientId: DhanHQ.configuration.client_id || ENV['DHAN_CLIENT_ID'] || ENV['CLIENT_ID']
```

### 2. **Configuration Normalization** (Enhanced)

**Issue**: Gem expects `DHAN_` prefix, but codebase was using `DHANHQ_` prefix inconsistently.

**Fix**: Added comprehensive normalization in initializer to support both naming conventions for all gem options.

## Recommended Environment Variables

### Minimum Required
```bash
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token
# or
DHAN_CLIENT_ID=your_client_id
DHAN_ACCESS_TOKEN=your_access_token
```

### Recommended for Production
```bash
# Credentials (use either naming convention)
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token

# Logging
DHAN_LOG_LEVEL=INFO  # or DEBUG for troubleshooting

# Order Placement Control
ENABLE_ORDER=true  # Set to true to enable actual order placement

# WebSocket Configuration
DHANHQ_WS_MODE=quote  # quote, ticker, or full
```

### Optional Advanced Configuration
```bash
# API Endpoints (if using custom/sandbox endpoints)
DHAN_BASE_URL=https://api.dhan.co/v2
DHAN_WS_ORDER_URL=wss://api-order-update.dhan.co
DHAN_WS_MARKET_FEED_URL=wss://api-feed.dhan.co

# Partner Mode (if applicable)
DHAN_WS_USER_TYPE=PARTNER
DHAN_PARTNER_ID=your_partner_id
DHAN_PARTNER_SECRET=your_partner_secret

# Market Depth (if using depth feeds)
DHAN_WS_MARKET_DEPTH_URL=wss://depth-api-feed.dhan.co/twentydepth
DHAN_MARKET_DEPTH_LEVEL=20  # or 200
```

## Testing Configuration

### Verify Configuration is Loaded

```ruby
# In Rails console
DhanHQ.configuration.client_id
DhanHQ.configuration.access_token
Rails.application.config.x.dhanhq
```

### Check Environment Variables

```bash
# Check if credentials are set
echo $CLIENT_ID
echo $ACCESS_TOKEN
# or
echo $DHAN_CLIENT_ID
echo $DHAN_ACCESS_TOKEN
```

### Health Check Endpoint

```bash
curl http://localhost:3000/api/health
```

The health endpoint will show credential status in the response.

## Migration Guide

### From Old Configuration

If you were using `DHAN_CLIENT_ID` and `DHAN_ACCESS_TOKEN`, no changes needed - both naming conventions are now supported.

### To New Configuration

You can now use either:
- `CLIENT_ID` / `ACCESS_TOKEN` (gem's preferred)
- `DHAN_CLIENT_ID` / `DHAN_ACCESS_TOKEN` (codebase convention)

Both work identically.

## Best Practices

1. **Use `DhanHQ.configuration.client_id`** in application code instead of direct ENV access
2. **Set `ENABLE_ORDER=true`** only in production after thorough testing
3. **Use `DHAN_LOG_LEVEL=DEBUG`** for troubleshooting, `INFO` for production
4. **Store credentials in encrypted credentials** or environment variables, never in code
5. **Test with paper trading** (`PAPER_MODE=true`) before live trading

## References

- DhanHQ Gem Documentation: `docs/dhanhq-client.md`
- Initializer: `config/initializers/dhanhq_config.rb`
- Order Placement: `app/services/orders/placer.rb`
- Health Check: `app/controllers/api/health_controller.rb`

