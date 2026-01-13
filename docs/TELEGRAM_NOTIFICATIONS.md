# Telegram Notifications - Complete Guide

## Overview

The Telegram notification system sends real-time notifications to Telegram for:
- **Entry events**: When a new position is entered
- **Exit events**: When a position is exited (with reason)
- **PnL milestones**: When PnL reaches configured thresholds (e.g., +10%, +20%, etc.)
- **Risk alerts**: Important risk-related notifications

The Telegram notifier has been refactored to use a simple `Net::HTTP` implementation with automatic message chunking. It's available in two ways:

1. **Direct class methods** - `TelegramNotifier.send_message()` and `TelegramNotifier.send_chat_action()`
2. **ApplicationService helpers** - `notify()` and `typing_ping()` available in all services

## Setup

### 1. Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot` command
3. Follow the instructions to create your bot
4. Copy the bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### 2. Get Your Chat ID

1. Search for [@userinfobot](https://t.me/userinfobot) on Telegram
2. Start a conversation with the bot
3. It will reply with your chat ID (a numeric value like `123456789`)

Alternatively, you can:
- Send a message to your bot
- Visit `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
- Look for the `chat.id` field in the response

### 3. Configure Environment Variables

Add the following to your `.env` file:

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

### 4. Configure in `config/algo.yml`

The Telegram configuration is already added to `config/algo.yml`:

```yaml
telegram:
  enabled: true # Set to false to disable Telegram notifications
  pnl_update_interval_seconds: 300 # Minimum seconds between PnL update notifications per position
  notify_entry: true # Send notifications on entry
  notify_exit: true # Send notifications on exit
  notify_pnl_updates: false # Send periodic PnL updates (throttled)
  notify_pnl_milestones: true # Send notifications for PnL milestones (10%, 20%, etc.)
  pnl_milestones: [10, 20, 30, 50, 100] # PnL percentage milestones to notify
  notify_risk_alerts: true # Send risk alert notifications
```

## Usage

### Quick Start

#### In Any Service (ApplicationService)

All services that inherit from `ApplicationService` automatically have access to Telegram notification helpers:

```ruby
# frozen_string_literal: true

module Orders
  class EntryManager < ApplicationService
    def call
      # Send a notification with optional tag
      notify("Order placed successfully", tag: "ORDER_PLACED")

      # Send typing indicator
      typing_ping

      # Regular logging (also available)
      log_info("Processing order")
    end
  end
end
```

#### Direct Usage

```ruby
# Send a simple message
TelegramNotifier.send_message("Hello from Telegram!")

# Send with HTML formatting
TelegramNotifier.send_message("Hello <b>bold</b> text", parse_mode: 'HTML')

# Send typing indicator
TelegramNotifier.send_chat_action(action: 'typing')

# Check if enabled
if TelegramNotifier.enabled?
  TelegramNotifier.send_message("Telegram is configured!")
end
```

### ApplicationService Helpers

#### `notify(message, tag: nil)`

Sends a message to Telegram with automatic class context:

```ruby
class MyService < ApplicationService
  def call
    # Simple notification
    notify("Task completed")

    # With tag for categorization
    notify("Stop loss hit", tag: "SL_HIT")
    notify("Take profit reached", tag: "TP")
  end
end
```

**Output format:**
- Without tag: `[MyService] Task completed`
- With tag: `[MyService] [SL_HIT]\n\nStop loss hit`

#### `typing_ping()`

Sends a typing indicator to show the bot is processing:

```ruby
class MyService < ApplicationService
  def call
    typing_ping  # Shows "typing..." in Telegram
    # Do some work...
    notify("Work completed")
  end
end
```

#### Logging Helpers

Also available in `ApplicationService`:

```ruby
log_info("Information message")
log_warn("Warning message")
log_error("Error message")
log_debug("Debug message")
```

All log messages are automatically prefixed with `[ClassName]`.

### Features

#### Automatic Message Chunking

Messages longer than 4000 characters are automatically split into multiple messages:

```ruby
# This will be split into multiple messages if needed
long_message = "Very long text... " * 1000
TelegramNotifier.send_message(long_message)
```

#### Backward Compatibility

The old `Notifications::TelegramNotifier.instance` interface still works:

```ruby
# Old way (still works)
Notifications::TelegramNotifier.instance.notify_entry(tracker, entry_data)
Notifications::TelegramNotifier.instance.send_test_message("Test")
```

## Notification Types

### Entry Notifications

Sent when a new position is entered. Includes:
- Symbol and index
- Entry price and quantity
- Direction (BUY/SELL)
- Risk percentage (if available)
- Stop loss and take profit levels
- Order number
- Timestamp

**Example:**
```
🟢 ENTRY

📊 Symbol: NIFTY25JAN24500CE
📈 Index: NIFTY
💰 Entry Price: ₹125.50
📦 Quantity: 50
🎯 Direction: BUY
⚖️ Risk: 1.00%
🛑 SL: ₹87.85
🎯 TP: ₹200.80
🆔 Order No: ORD123456
⏰ Time: 14:30:25
```

### Exit Notifications

Sent when a position is exited. Includes:
- Symbol
- Entry and exit prices
- Quantity
- Final PnL (absolute and percentage)
- Exit reason (e.g., "SL HIT 30.00%", "TP HIT 60.00%", "TRAILING STOP drop=3.0")
- Order number
- Timestamp

**Example:**
```
✅ EXIT

📊 Symbol: NIFTY25JAN24500CE
💰 Entry: ₹125.50
💵 Exit: ₹200.80
📦 Quantity: 50
💸 PnL: ₹3,765.00 (📈 60.00%)
📝 Reason: TP HIT 60.00%
🆔 Order No: ORD123456
⏰ Time: 15:45:10
```

### PnL Milestone Notifications

Sent when PnL reaches configured percentage thresholds. Default milestones: 10%, 20%, 30%, 50%, 100%.

**Example:**
```
🎯 Milestone Reached

📊 Symbol: NIFTY25JAN24500CE
🏆 Milestone: 20% profit
💸 PnL: ₹1,255.00 (+20.00%)
🆔 Order No: ORD123456
⏰ Time: 15:20:15
```

### Risk Alert Notifications

Sent for important risk-related events (future feature).

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Master toggle for Telegram notifications |
| `notify_entry` | `true` | Send notifications on entry |
| `notify_exit` | `true` | Send notifications on exit |
| `notify_pnl_updates` | `false` | Send periodic PnL updates (throttled) |
| `notify_pnl_milestones` | `true` | Send notifications for PnL milestones |
| `pnl_milestones` | `[10, 20, 30, 50, 100]` | PnL percentage thresholds to notify |
| `pnl_update_interval_seconds` | `300` | Minimum seconds between PnL updates per position |
| `notify_risk_alerts` | `true` | Send risk alert notifications |

## Examples

### Example 1: Service with Notifications

```ruby
# frozen_string_literal: true

module Risk
  class StopLossChecker < ApplicationService
    def initialize(tracker)
      @tracker = tracker
    end

    def call
      if stop_loss_hit?
        notify("Stop loss triggered for #{@tracker.symbol}", tag: "SL_HIT")
        execute_exit
      end
    end

    private

    def stop_loss_hit?
      # Check logic
    end

    def execute_exit
      # Exit logic
    end
  end
end
```

### Example 2: Long Running Process

```ruby
# frozen_string_literal: true

module Optimization
  class Backtester < ApplicationService
    def call
      notify("Starting backtest...", tag: "BACKTEST_START")

      results = []
      100.times do |i|
        typing_ping if (i % 10).zero? # Show typing every 10 iterations
        results << run_iteration(i)
      end

      notify("Backtest completed: #{results.size} iterations", tag: "BACKTEST_COMPLETE")
      results
    end
  end
end
```

### Example 3: Error Handling

```ruby
# frozen_string_literal: true

module Orders
  class Placer < ApplicationService
    def call
      begin
        place_order
        notify("Order placed successfully", tag: "SUCCESS")
      rescue StandardError => e
        notify("Order failed: #{e.message}", tag: "ERROR")
        log_error("Order placement failed: #{e.class} - #{e.message}")
        raise
      end
    end
  end
end
```

## Migration from Old API

If you're using the old `Notifications::TelegramNotifier.instance` interface, you can gradually migrate:

**Old way:**
```ruby
Notifications::TelegramNotifier.instance.notify_risk_alert("Alert message")
```

**New way (if in ApplicationService):**
```ruby
notify("Alert message", tag: "RISK_ALERT")
```

**Or direct:**
```ruby
TelegramNotifier.send_message("Alert message")
```

Both ways work, so you can migrate at your own pace.

## Disabling Notifications

To disable Telegram notifications:

1. Set `enabled: false` in `config/algo.yml`:
   ```yaml
   telegram:
     enabled: false
   ```

2. Or remove/unset the environment variables:
   ```bash
   # Remove or comment out
   # TELEGRAM_BOT_TOKEN=
   # TELEGRAM_CHAT_ID=
   ```

## Troubleshooting

### Current Status

Based on diagnostic tests:
- ✅ Bot token is valid: `@my_alert_system_bot` (ID: 7590450232)
- ✅ Chat ID is configured: `5862585229`
- ✅ Messages are being sent successfully (Message IDs: 16365, 16366, 16367)
- ✅ Telegram API is responding correctly

### If You're Not Receiving Messages

#### Step 1: Verify You're Checking the Correct Chat

1. Open Telegram
2. Search for `@my_alert_system_bot`
3. Make sure you're in the chat with this bot (not a different bot)

#### Step 2: Start a Conversation with the Bot

1. Open the chat with `@my_alert_system_bot`
2. Send `/start` to the bot
3. Wait for a response
4. Run the test script again:
   ```bash
   bin/rails runner scripts/test_telegram_simple.rb
   ```

#### Step 3: Check if Bot is Blocked

1. In Telegram, go to Settings → Privacy and Security → Blocked Users
2. Check if `@my_alert_system_bot` is in the blocked list
3. If blocked, unblock it

#### Step 4: Verify Chat ID

The configured chat ID is: `5862585229`

To verify this is correct:
1. Send a message to `@my_alert_system_bot`
2. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. Look for `"chat":{"id": <number>}` in the response
4. Compare with your configured chat ID

**Note:** If you have a webhook active, you'll need to delete it first:
```bash
curl "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/deleteWebhook"
```

#### Step 5: Test Direct API Call

Test sending a message directly via API:

```bash
curl -X POST "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/sendMessage" \
  -d "chat_id=5862585229" \
  -d "text=Direct API test message"
```

If this works, the issue is in the application code. If it doesn't, the issue is with Telegram configuration.

### Test Scripts Available

#### 1. Simple Test (Plain Text)
```bash
bin/rails runner scripts/test_telegram_simple.rb
```

#### 2. Full Diagnostic
```bash
bin/rails runner scripts/diagnose_telegram.rb
```

#### 3. Direct Notifier Test
```bash
bin/rails runner scripts/test_telegram_notifier_direct.rb
```

#### 4. Complete Test Suite
```bash
bin/rails runner scripts/test_telegram_notifier.rb
```

#### 5. Test New API
```bash
bin/rails runner scripts/test_new_telegram_api.rb
```

### Quick Test from Rails Console

```ruby
# Check if enabled
notifier = Notifications::TelegramNotifier.instance
notifier.enabled? # Should return true

# Send test message
notifier.send_test_message("Hello from console!")

# Send typing indicator
notifier.send_typing_indicator(duration: 3)

# Send risk alert
notifier.notify_risk_alert("Test alert", severity: 'info')
```

### Common Issues

#### Issue: "chat not found" Error
**Solution:**
- Make sure you've sent at least one message to the bot
- Verify the chat ID is correct
- Check that you're using the correct bot token

#### Issue: "401 Unauthorized" Error
**Solution:**
- Check that `TELEGRAM_BOT_TOKEN` is correct
- Get a new token from @BotFather if needed

#### Issue: Messages Sent but Not Received
**Possible Causes:**
1. Wrong chat - Check you're looking at the correct bot chat
2. Bot blocked - Unblock the bot in Telegram settings
3. Wrong chat ID - Verify chat ID matches your current chat
4. Bot not started - Send `/start` to the bot first

#### Issue: Webhook Conflict
If you see "can't use getUpdates while webhook is active":
- This is normal if you have a webhook configured
- Messages will still work via `sendMessage` API
- To use `getUpdates`, delete the webhook first

#### Issue: Notifications Not Sending
1. **Check environment variables**: Ensure `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are set correctly
2. **Check configuration**: Verify `telegram.enabled` is `true` in `config/algo.yml`
3. **Check logs**: Look for `[TelegramNotifier]` messages in Rails logs
4. **Verify bot token**: Ensure the bot token is correct and the bot is active
5. **Verify chat ID**: Ensure the chat ID is correct and you've sent at least one message to the bot

#### Issue: LoadError: cannot load such file -- telegram/bot
**Solution:**
- Run `bundle install` to install the gem

### Still Not Working?

1. Check Rails logs for errors:
   ```bash
   tail -f log/development.log | grep TelegramNotifier
   ```

2. Verify environment variables are loaded:
   ```bash
   bin/rails runner "puts ENV['TELEGRAM_BOT_TOKEN']"
   bin/rails runner "puts ENV['TELEGRAM_CHAT_ID']"
   ```

3. Test with curl directly:
   ```bash
   curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
     -d "chat_id=<CHAT_ID>" \
     -d "text=Test"
   ```

4. Check bot status with @BotFather:
   - Send `/mybots` to @BotFather
   - Select your bot
   - Check bot status

### Verification Checklist

- [ ] Bot token is set in environment (`TELEGRAM_BOT_TOKEN`)
- [ ] Chat ID is set in environment (`TELEGRAM_CHAT_ID`)
- [ ] Bot is not blocked in Telegram
- [ ] You've sent `/start` to the bot
- [ ] You're checking the correct chat (`@my_alert_system_bot`)
- [ ] Test scripts run without errors
- [ ] Direct API call works (curl test)

## Implementation Details

### Service Location

The Telegram notification service is located at:
- `lib/notifications/telegram_notifier.rb`
- `lib/telegram_notifier.rb`

### Integration Points

Notifications are integrated into:
- `app/services/orders/entry_manager.rb` - Entry notifications
- `app/services/live/exit_engine.rb` - Exit notifications
- `app/services/live/pnl_updater_service.rb` - PnL milestone notifications

### Thread Safety

The TelegramNotifier uses a mutex to ensure thread-safe message sending, making it safe for use in multi-threaded environments.

### Error Handling

All notification methods include error handling to prevent failures from affecting the trading system. Errors are logged but do not raise exceptions.

## Future Enhancements

Potential future enhancements:
- Periodic PnL summary notifications
- Daily trading summary
- Risk alert notifications for drawdowns, daily limits, etc.
- Configurable notification templates
- Multiple chat ID support
- Notification filtering by index or symbol

