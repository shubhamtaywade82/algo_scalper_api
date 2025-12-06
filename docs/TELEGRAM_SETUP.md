# Telegram Bot Setup for Swing Trading Notifications

This guide will help you set up a Telegram bot to receive swing trading recommendations.

## Prerequisites

- A Telegram account
- Access to environment variables configuration

## Step-by-Step Setup

### 1. Create a Telegram Bot

1. Open Telegram and search for **[@BotFather](https://t.me/botfather)**
2. Start a conversation with BotFather
3. Send the command: `/newbot`
4. Follow the prompts:
   - Choose a name for your bot (e.g., "Swing Trading Bot")
   - Choose a username (must end with `bot`, e.g., "swing_trading_bot")
5. BotFather will provide you with a **bot token** (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)
   - **Save this token securely** - you'll need it for configuration

### 2. Get Your Chat ID

You need to find your Telegram chat ID to receive messages. There are two methods:

#### Method 1: Using @userinfobot (Easiest)

1. Search for **[@userinfobot](https://t.me/userinfobot)** on Telegram
2. Start a conversation
3. The bot will immediately reply with your user information
4. Look for the **ID** field - this is your chat ID (a number like `123456789`)

#### Method 2: Using Your Bot

1. Start a conversation with your newly created bot
2. Send any message to your bot (e.g., "Hello")
3. Open your browser and visit:
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
   Replace `<YOUR_BOT_TOKEN>` with the token you got from BotFather
4. Look for a JSON response containing `"chat":{"id":123456789}`
5. The number after `"id":` is your chat ID

**Note:** If you get an empty response `{"ok":true,"result":[]}`, send another message to your bot and refresh the URL.

### 3. Configure Environment Variables

Add the following environment variables to your application:

**Option 1: Using .env file (Development)**
```bash
# Add to .env file
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

**Option 2: Using environment variables (Production)**
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token_here"
export TELEGRAM_CHAT_ID="your_chat_id_here"
```

**Alternative variable names (also supported):**
- `SWING_TRADING_TELEGRAM_BOT_TOKEN` instead of `TELEGRAM_BOT_TOKEN`
- `SWING_TRADING_TELEGRAM_CHAT_ID` instead of `TELEGRAM_CHAT_ID`

### 4. Test the Configuration

You can test the Telegram notification setup:

**Option 1: Manual Analysis**
```bash
# Trigger analysis for a watchlist item
curl -X POST http://localhost:3000/api/swing_trading/recommendations/analyze/1?type=swing
```

**Option 2: Using Rake Task**
```bash
rake swing_trading:analyze_watchlist
```

If a recommendation is generated with a confidence score ≥ 70%, you should receive a Telegram message.

### 5. Verify Notification Format

When you receive a notification, it should include:

- 🟢/🔴 Direction indicator (Buy/Sell)
- ⚡/📈 Type indicator (Swing/Long-term)
- Trade details (Entry, SL, TP, Quantity, Investment, Allocation)
- Technical analysis summary (Supertrend, ADX, RSI, MACD)
- Volume analysis
- Confidence score
- Reasoning
- Analysis timestamp and expiration

## Notification Criteria

Telegram notifications are sent automatically when:
- A new recommendation is generated
- The recommendation has a confidence score ≥ 70%
- The recommendation is active (not expired or cancelled)

## Troubleshooting

### No Notifications Received

1. **Check Environment Variables**
   ```bash
   echo $TELEGRAM_BOT_TOKEN
   echo $TELEGRAM_CHAT_ID
   ```
   Both should show your configured values.

2. **Check Bot Token**
   - Verify the token is correct (no extra spaces)
   - Ensure the bot is still active (check with BotFather)

3. **Check Chat ID**
   - Verify the chat ID is correct (should be a number)
   - Make sure you've sent at least one message to your bot

4. **Check Logs**
   ```bash
   # Look for Telegram notification errors
   tail -f log/development.log | grep Telegram
   ```

5. **Check Confidence Score**
   - Notifications only sent for confidence ≥ 70%
   - Check recommendation confidence: `rake swing_trading:list_recommendations`

### "Telegram bot token not configured" Error

- Ensure `TELEGRAM_BOT_TOKEN` or `SWING_TRADING_TELEGRAM_BOT_TOKEN` is set
- Restart your application after setting environment variables

### "Telegram chat ID not configured" Error

- Ensure `TELEGRAM_CHAT_ID` or `SWING_TRADING_TELEGRAM_CHAT_ID` is set
- Verify the chat ID is a valid number

### "Telegram API error" Messages

- Check your internet connection
- Verify the bot token is correct
- Ensure the chat ID is correct
- Check Telegram API status: https://status.telegram.org/

### Bot Not Responding

- Make sure you've started a conversation with your bot
- Send `/start` command to your bot
- Verify the bot is not blocked or deleted

## Security Best Practices

1. **Never commit tokens to version control**
   - Add `.env` to `.gitignore`
   - Use environment variables in production

2. **Use separate bots for different environments**
   - Development bot for testing
   - Production bot for live notifications

3. **Rotate tokens periodically**
   - Use BotFather's `/revoke` command to generate new tokens
   - Update environment variables accordingly

4. **Limit bot access**
   - Only share bot token with authorized personnel
   - Use separate chat IDs for different team members if needed

## Advanced Configuration

### Multiple Chat IDs

To send notifications to multiple Telegram chats, you can modify the `TelegramNotifier` service to accept multiple chat IDs:

```ruby
# In app/services/swing_trading/telegram_notifier.rb
@chat_ids = ENV['TELEGRAM_CHAT_IDS']&.split(',') || [ENV['TELEGRAM_CHAT_ID']]
```

Then set `TELEGRAM_CHAT_IDS` as comma-separated values:
```bash
TELEGRAM_CHAT_IDS=123456789,987654321,111222333
```

### Custom Notification Threshold

To change the confidence threshold for notifications, modify the scheduler:

```ruby
# In app/services/swing_trading/scheduler.rb
if recommendation.confidence_score && recommendation.confidence_score >= 0.8  # Changed from 0.7
```

## Example Notification

Here's what a typical notification looks like:

```
🟢 BUY RELIANCE ⚡
Swing Recommendation

💰 Trade Details
Entry: ₹2450.50
Stop Loss: ₹2376.99
Take Profit: ₹2597.53
Quantity: 4 shares
Investment: ₹9802.0
Allocation: 10.0%
Hold Duration: 3 days
Risk-Reward: 2.0:1

📊 Technical Analysis
• Supertrend: BULLISH
• ADX: 28.5 (moderate)
• RSI: 65.2
• MACD: BUY

📈 Volume Analysis
• Trend: Increasing
• Volume Ratio: 1.2
• Current Volume: 1,800,000

🎯 Confidence Score: 75.0%

💡 Reasoning
• BUY signal generated based on technical analysis:
• Supertrend indicates bullish trend
• ADX shows moderate trend strength (28.5)
• RSI is bullish (65.2)
• MACD shows bullish momentum
• Volume trend is increasing (ratio: 1.2)
• Confidence score: 75.0%
• Recommended hold duration: 3 days

⏰ Analysis Time: 2024-12-06 12:30:45
⏳ Expires: 2024-12-09 12:30:45
```

## Support

If you encounter issues:
1. Check the application logs for detailed error messages
2. Verify all configuration steps were completed correctly
3. Test the bot token and chat ID using the Telegram API directly
4. Ensure your application has internet access to reach Telegram API
