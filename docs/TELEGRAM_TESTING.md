# Testing Telegram Notifications

This guide explains how to test the Telegram notification system locally.

## Prerequisites

1. **Telegram Bot Token**: Get from [@BotFather](https://t.me/BotFather)
2. **Chat ID**: Get from [@userinfobot](https://t.me/userinfobot)
3. **Environment Variables**: Set in `.env` file or export in terminal

## Quick Test (Simple - No Rails)

For a quick test without loading the full Rails environment:

```bash
# Set environment variables
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"

# Run simple test
ruby scripts/test_telegram_simple.rb
```

This will:
- Test basic Telegram API connectivity
- Send a simple test message
- Show clear error messages if something fails

## Full Test (With Rails)

For a comprehensive test that uses the actual TelegramNotifier service:

```bash
# Option 1: Using Rails runner
rails runner scripts/test_telegram_notifier.rb

# Option 2: Using Rake task
rake telegram:test
```

This will test:
1. ✅ Simple test message
2. ✅ Entry notification format
3. ✅ Exit notification format
4. ✅ PnL milestone notification
5. ✅ Risk alert notification

## Setting Up Environment Variables

### Option 1: Using .env file

Create or edit `.env` file in the project root:

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

### Option 2: Export in terminal

```bash
export TELEGRAM_BOT_TOKEN="your_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
```

### Option 3: Load from .env in Rails

If using `dotenv-rails`, the `.env` file will be automatically loaded.

## Getting Your Bot Token

1. Open Telegram and search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot`
3. Follow instructions to name your bot
4. Copy the token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

## Getting Your Chat ID

### Method 1: Using @userinfobot
1. Search for [@userinfobot](https://t.me/userinfobot)
2. Start conversation
3. It will reply with your chat ID

### Method 2: Using API
1. Send a message to your bot
2. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. Look for `"chat":{"id":123456789}` in the response

## Troubleshooting

### Error: "Missing required environment variables"
- Ensure `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are set
- Check that `.env` file is in the project root
- Verify environment variables are exported in your terminal

### Error: "401 Unauthorized"
- Bot token is incorrect
- Token may have been revoked
- Get a new token from @BotFather

### Error: "400 Bad Request: chat not found"
- Chat ID is incorrect
- You haven't sent a message to the bot yet
- Send `/start` to your bot first, then try again

### Error: "403 Forbidden"
- You may have blocked the bot
- Bot may not have permission to send messages
- Unblock the bot and try again

### Error: "LoadError: cannot load such file -- telegram/bot"
- Install the gem: `bundle install`
- Ensure `telegram-bot-ruby` is in your Gemfile

### Notifications not sending in production
- Check Rails logs for `[TelegramNotifier]` messages
- Verify `telegram.enabled` is `true` in `config/algo.yml`
- Check that environment variables are set in production environment

## Expected Output

### Successful Test Output

```
================================================================================
Telegram Notifier Test
================================================================================

Environment Check:
  TELEGRAM_BOT_TOKEN: ✓ Set
  TELEGRAM_CHAT_ID: ✓ Set

Initializing TelegramNotifier...
  ✓ Notifier initialized
  Enabled: Yes

Test 1: Sending simple test message...
  ✓ Test message sent successfully!
  Check your Telegram for the message.

Test 2: Testing entry notification format...
  ✓ Entry notification sent successfully!
  Check your Telegram for the entry notification.

[... more tests ...]

================================================================================
Test Summary
================================================================================
All tests completed. Check your Telegram for notifications.
================================================================================
```

### Failed Test Output

```
Environment Check:
  TELEGRAM_BOT_TOKEN: ✗ Missing
  TELEGRAM_CHAT_ID: ✗ Missing

❌ ERROR: Missing required environment variables!

Please set the following in your .env file or environment:
  TELEGRAM_BOT_TOKEN=your_bot_token
  TELEGRAM_CHAT_ID=your_chat_id
```

## Testing Individual Notification Types

You can also test individual notification types by creating a simple script:

```ruby
# test_entry.rb
require_relative 'config/environment'

notifier = Notifications::TelegramNotifier.instance
mock_tracker = OpenStruct.new(
  order_no: 'TEST-001',
  symbol: 'NIFTY25JAN24500CE',
  entry_price: BigDecimal('125.50'),
  quantity: 50,
  direction: 'bullish',
  index_key: 'NIFTY'
)

entry_data = {
  symbol: 'NIFTY25JAN24500CE',
  entry_price: 125.50,
  quantity: 50,
  direction: :bullish,
  index_key: 'NIFTY',
  risk_pct: 0.01,
  sl_price: 87.85,
  tp_price: 200.80
}

notifier.notify_entry(mock_tracker, entry_data)
```

## Next Steps

After successful testing:
1. Verify notifications are working in your development environment
2. Test with actual trading events (entry/exit)
3. Configure notification preferences in `config/algo.yml`
4. Deploy to production with proper environment variables
