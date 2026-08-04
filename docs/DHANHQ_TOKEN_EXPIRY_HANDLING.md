# DhanHQ Token Expiry Handling

**Date**: 2025-01-06
**Purpose**: Automatically detect and notify when DhanHQ access token expires

---

## Overview

The system now automatically detects when the DhanHQ access token expires (error code `DH-901` or `401`) and sends a Telegram notification to alert administrators. This prevents silent failures when API calls fail due to expired credentials.

---

## Implementation

### 1. Error Handler Module

**File**: `app/services/concerns/dhanhq_error_handler.rb`

A new concern module that:
- Detects token expiry errors (DH-901, 401, and related keywords)
- Sends Telegram notifications with actionable information
- Implements a cooldown mechanism (1 hour) to prevent notification spam

**Key Methods**:
- `token_expired?(error)` - Detects if error indicates token expiry
- `notify_token_expiry(context:, error:)` - Sends Telegram notification
- `handle_dhanhq_error(error, context:)` - Main handler that detects and notifies

### 2. Integration Points

The error handler is integrated into all DhanHQ API call sites:

#### `app/models/concerns/instrument_helpers.rb`
- `intraday_ohlc()` - Historical OHLC data fetching
- `ohlc()` - Current OHLC data
- `fetch_ltp_from_api()` - LTP fetching (excluding rate limit errors)

#### `app/models/instrument.rb`
- `fetch_fresh_option_chain()` - Option chain data fetching

---

## Error Detection

The handler detects token expiry through:

1. **Error Codes**:
   - `DH-901` - DhanHQ token expiry code
   - `401` - HTTP unauthorized

2. **Error Keywords** (case-insensitive):
   - "access token.*expired"
   - "token.*invalid"
   - "Client ID.*invalid"
   - "authentication.*failed"
   - "unauthorized"

---

## Notification Format

When token expiry is detected, a Telegram message is sent:

```
🚨 **DhanHQ Access Token Expired**

**Context:** [where error occurred]
**Error:** [error message]

**Action Required:**
1. Generate new access token from DhanHQ
2. Update `DHANHQ_ACCESS_TOKEN` environment variable
3. Restart services

**Note:** This notification will be sent again after 1 hour if issue persists.
```

---

## Cooldown Mechanism

To prevent notification spam:
- **Cooldown Period**: 1 hour
- **Storage**: Rails cache with key `dhanhq_token_expiry_notification_sent`
- **Behavior**: Only sends notification if last notification was > 1 hour ago

---

## Usage Example

```ruby
# In any method that calls DhanHQ API:
begin
  data = DhanHQ::Models::SomeModel.fetch(...)
rescue StandardError => e
  error_info = Concerns::DhanhqErrorHandler.handle_dhanhq_error(
    e,
    context: "method_name(Instrument #{id})"
  )
  # error_info contains: { error:, message:, token_expired: }
  nil
end
```

---

## Testing

To test token expiry detection:

1. **Set invalid token**:
   ```bash
   export DHANHQ_ACCESS_TOKEN="invalid_token"
   ```

2. **Trigger API call**:
   ```ruby
   instrument = Instrument.segment_index.find_by(security_id: 13)
   instrument.intraday_ohlc(interval: '5')
   ```

3. **Check Telegram**:
   - Should receive notification within seconds
   - Subsequent calls within 1 hour should not trigger new notifications

---

## Configuration

### Required Environment Variables

- `TELEGRAM_BOT_TOKEN` - Telegram bot token
- `TELEGRAM_CHAT_ID` - Telegram chat ID for notifications

### Optional Configuration

The cooldown period can be adjusted in `dhanhq_error_handler.rb`:
```ruby
NOTIFICATION_COOLDOWN = 1.hour  # Change as needed
```

---

## Files Modified

1. **New File**: `app/services/concerns/dhanhq_error_handler.rb`
   - Error detection and notification logic

2. **Modified**: `app/models/concerns/instrument_helpers.rb`
   - Added error handling to `intraday_ohlc()`, `ohlc()`, `fetch_ltp_from_api()`

3. **Modified**: `app/models/instrument.rb`
   - Added error handling to `fetch_fresh_option_chain()`

---

## Benefits

1. **Proactive Alerting**: Administrators are immediately notified when token expires
2. **Actionable Information**: Notification includes clear steps to resolve
3. **No Spam**: Cooldown prevents notification flooding
4. **Comprehensive Coverage**: All DhanHQ API call sites are protected
5. **Graceful Degradation**: System continues to function (returns nil) while alerting

---

## Future Enhancements

Potential improvements:
- Auto-retry with exponential backoff
- Integration with credential refresh service (if available)
- Metrics/alerting dashboard integration
- Support for multiple notification channels (email, Slack, etc.)

---

## Troubleshooting

### Notifications Not Sending

1. **Check Telegram Configuration**:
   ```ruby
   TelegramNotifier.enabled?  # Should return true
   ```

2. **Check Cache**:
   ```ruby
   Rails.cache.read('dhanhq_token_expiry_notification_sent')
   # If present, wait for cooldown to expire
   ```

3. **Check Logs**:
   ```bash
   grep "DhanhqErrorHandler" log/development.log
   ```

### False Positives

If non-token errors trigger notifications:
- Review error message patterns in `TOKEN_EXPIRY_KEYWORDS`
- Adjust detection logic in `token_expired?()` method

---

## Related Documentation

- [Telegram Notifications](./TELEGRAM_NOTIFICATIONS.md)
- [DhanHQ Configuration](../config/initializers/dhanhq_config.rb)
- [Error Handling Standards](../CODING_CONVENTIONS.md#error-handling-rules)

