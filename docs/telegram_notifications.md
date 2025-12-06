# Telegram Notifications

This document describes the Telegram notification system for bot actions in the Algo Scalper API.

## Overview

The Telegram notification system sends real-time notifications to Telegram for:
- **Entry events**: When a new position is entered
- **Exit events**: When a position is exited (with reason)
- **PnL milestones**: When PnL reaches configured thresholds (e.g., +10%, +20%, etc.)
- **Risk alerts**: Important risk-related notifications

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

### 4. Install Dependencies

Run:

```bash
bundle install
```

This will install the `telegram-bot-ruby` gem.

### 5. Configure in `config/algo.yml`

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

### Notifications Not Sending

1. **Check environment variables**: Ensure `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are set correctly
2. **Check configuration**: Verify `telegram.enabled` is `true` in `config/algo.yml`
3. **Check logs**: Look for `[TelegramNotifier]` messages in Rails logs
4. **Verify bot token**: Ensure the bot token is correct and the bot is active
5. **Verify chat ID**: Ensure the chat ID is correct and you've sent at least one message to the bot

### Common Errors

- **`LoadError: cannot load such file -- telegram/bot`**: Run `bundle install` to install the gem
- **`401 Unauthorized`**: Check that `TELEGRAM_BOT_TOKEN` is correct
- **`400 Bad Request: chat not found`**: Check that `TELEGRAM_CHAT_ID` is correct and you've messaged the bot

## Implementation Details

### Service Location

The Telegram notification service is located at:
- `lib/notifications/telegram_notifier.rb`

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
