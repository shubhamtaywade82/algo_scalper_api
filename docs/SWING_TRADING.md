# Swing Trading & Long-Term Trading Automation

This document describes the swing trading and long-term trading automation system that monitors watchlist stocks and provides buy/sell recommendations based on technical analysis.

## Overview

The system analyzes stocks in your watchlist using multiple technical indicators (Supertrend, ADX, RSI, MACD) and volume analysis to generate trading recommendations. It supports both swing trading (3-5 day holds) and long-term trading (15+ day holds).

## Features

- **Automated Analysis**: Periodically analyzes watchlist stocks using technical indicators
- **Volume Analysis**: Uses volume data from DhanHQ APIs to identify high-probability entries
- **Comprehensive Recommendations**: Provides entry price, stop loss, take profit, quantity, allocation percentage, and hold duration
- **Technical Analysis Details**: Includes Supertrend, ADX, RSI, MACD, and volume analysis
- **Risk Management**: Calculates risk-reward ratios and allocation percentages
- **Telegram Notifications**: Sends notifications to Telegram bot for high-confidence recommendations (≥70%)

## Database Schema

### SwingTradingRecommendation Model

Stores all trading recommendations with the following key fields:

- `entry_price`: Recommended entry price
- `stop_loss`: Stop loss price
- `take_profit`: Take profit target
- `quantity`: Recommended quantity
- `allocation_pct`: Percentage of capital to allocate
- `hold_duration_days`: Expected hold duration
- `confidence_score`: Confidence score (0.0 to 1.0)
- `technical_analysis`: JSONB field storing all indicator values
- `volume_analysis`: JSONB field storing volume analysis
- `reasoning`: Human-readable explanation of the recommendation

## API Endpoints

### Watchlist Management

#### GET /api/watchlist
List all active watchlist items.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "segment": "NSE_EQ",
      "security_id": "1333",
      "symbol_name": "RELIANCE",
      "kind": "equity",
      "active": true
    }
  ]
}
```

#### POST /api/watchlist
Add a stock to watchlist.

**Request Body:**
```json
{
  "watchlist_item": {
    "segment": "NSE_EQ",
    "security_id": "1333",
    "kind": "equity",
    "label": "Reliance Industries"
  }
}
```

#### DELETE /api/watchlist/:id
Remove a stock from watchlist (marks as inactive).

#### GET /api/watchlist/:id
Get watchlist item details with recent recommendations.

### Swing Trading Recommendations

#### GET /api/swing_trading/recommendations
List all active recommendations with optional filters.

**Query Parameters:**
- `type`: Filter by type (`swing` or `long_term`)
- `direction`: Filter by direction (`buy` or `sell`)
- `symbol`: Filter by symbol name
- `min_confidence`: Minimum confidence score (0.0 to 1.0)
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "symbol_name": "RELIANCE",
      "recommendation_type": "swing",
      "direction": "buy",
      "entry_price": 2450.50,
      "stop_loss": 2376.99,
      "take_profit": 2597.53,
      "quantity": 4,
      "allocation_pct": 10.0,
      "hold_duration_days": 3,
      "confidence_score": 0.75,
      "risk_reward_ratio": 2.0,
      "investment_amount": 9802.0,
      "technical_analysis": { ... },
      "volume_analysis": { ... },
      "reasoning": "..."
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 5,
    "total_pages": 1
  }
}
```

#### GET /api/swing_trading/recommendations/:id
Get detailed recommendation information.

#### POST /api/swing_trading/recommendations/:id/execute
Mark recommendation as executed.

#### POST /api/swing_trading/recommendations/:id/cancel
Cancel an active recommendation.

#### POST /api/swing_trading/recommendations/analyze/:watchlist_item_id
Manually trigger analysis for a watchlist item.

**Query Parameters:**
- `type`: Analysis type (`swing` or `long_term`, default: `swing`)

## Services

### SwingTrading::Analyzer

Analyzes a watchlist item and generates recommendations.

**Usage:**
```ruby
analyzer = SwingTrading::Analyzer.new(
  watchlist_item: watchlist_item,
  recommendation_type: 'swing' # or 'long_term'
)

result = analyzer.call
if result[:success]
  recommendation = result[:data]
  # Use recommendation data
end
```

**Analysis Process:**
1. Fetches intraday/historical OHLC data with volume from DhanHQ
2. Calculates technical indicators:
   - Supertrend (period: 10, multiplier: 3.0)
   - ADX (period: 14)
   - RSI (period: 14)
   - MACD (12, 26, 9)
3. Analyzes volume patterns
4. Determines signal direction (buy/sell) based on indicator confluence
5. Calculates entry, stop loss, take profit, quantity, and allocation
6. Generates confidence score and reasoning

### SwingTrading::Scheduler

Periodically monitors watchlist stocks and generates recommendations.

**Features:**
- Runs every 15 minutes
- Analyzes active watchlist items (equity stocks)
- Generates both swing and long-term recommendations
- Avoids duplicate analysis (skips if analyzed within last hour)
- Sends notifications for new recommendations

**Starting the Scheduler:**

Add to your application initialization (e.g., `config/initializers/swing_trading.rb`):

```ruby
if Rails.env.production? || Rails.env.development?
  SwingTrading::Scheduler.instance.start
end
```

Or use the rake task:

```bash
rake swing_trading:start_scheduler
```

### SwingTrading::TelegramNotifier

Sends notifications to Telegram bot for high-confidence recommendations.

**Configuration:**
Set environment variables:
- `TELEGRAM_BOT_TOKEN` or `SWING_TRADING_TELEGRAM_BOT_TOKEN`: Your Telegram bot token
- `TELEGRAM_CHAT_ID` or `SWING_TRADING_TELEGRAM_CHAT_ID`: Chat ID to send notifications to

**Usage:**
```ruby
telegram_notifier = SwingTrading::TelegramNotifier.new(recommendation: recommendation)
result = telegram_notifier.call

if result[:success]
  puts "Notification sent! Message ID: #{result[:data][:message_id]}"
else
  puts "Failed: #{result[:error]}"
end
```

**Notification Criteria:**
- Only sends notifications for recommendations with confidence score ≥ 70%
- Includes all trade details, technical analysis, volume analysis, and reasoning
- Formatted with Markdown for better readability

## Configuration

### Timeframes

- **Swing Trading**: Uses 15-minute candles, analyzes last 10 days
- **Long-Term Trading**: Uses 1-hour candles, analyzes last 30 days

### Risk Parameters

- **Stop Loss**: 3% from entry price
- **Take Profit**: 6% from entry price (2:1 risk-reward ratio)
- **Minimum Confidence**: 0.6 (60%)
- **Hold Duration**: 3 days (swing), 15 days (long-term)

### Allocation

- Base allocation: 10% (swing), 5% (long-term)
- Adjusted by confidence score
- Maximum: 20% (swing), 15% (long-term)

## Setup

1. **Run Migration:**
   ```bash
   rails db:migrate
   ```

2. **Add Stocks to Watchlist:**
   ```bash
   curl -X POST http://localhost:3000/api/watchlist \
     -H "Content-Type: application/json" \
     -d '{
       "watchlist_item": {
         "segment": "NSE_EQ",
         "security_id": "1333",
         "kind": "equity",
         "label": "Reliance Industries"
       }
     }'
   ```

3. **Start Scheduler:**
   ```bash
   rake swing_trading:start_scheduler
   ```

4. **View Recommendations:**
   ```bash
   curl http://localhost:3000/api/swing_trading/recommendations
   ```

## Technical Analysis Details

### Indicators Used

1. **Supertrend**
   - Period: 10
   - Multiplier: 3.0
   - Determines overall trend direction

2. **ADX (Average Directional Index)**
   - Period: 14
   - Measures trend strength
   - Values: <20 (weak), 20-40 (moderate), 40-60 (strong), >60 (very strong)

3. **RSI (Relative Strength Index)**
   - Period: 14
   - Oversold: <30 (bullish signal)
   - Overbought: >70 (bearish signal)

4. **MACD (Moving Average Convergence Divergence)**
   - Fast: 12, Slow: 26, Signal: 9
   - Bullish when MACD line crosses above signal line
   - Bearish when MACD line crosses below signal line

### Volume Analysis

- Compares recent average volume (last 20 candles) with historical average (previous 50 candles)
- Identifies increasing, decreasing, or stable volume trends
- Higher volume on breakouts increases confidence

### Signal Generation

Signals are generated when:
- Supertrend indicates clear trend direction
- ADX shows strong trend strength (≥20)
- RSI and/or MACD confirm the direction
- Volume analysis supports the trend

Confidence score is calculated based on:
- ADX strength (0-0.2)
- RSI confidence (0-0.15)
- MACD confidence (0-0.15)
- Volume confirmation (0-0.1)
- Base confidence (0.5)

## Example Recommendation

```json
{
  "id": 1,
  "symbol_name": "RELIANCE",
  "recommendation_type": "swing",
  "direction": "buy",
  "entry_price": 2450.50,
  "stop_loss": 2376.99,
  "take_profit": 2597.53,
  "quantity": 4,
  "allocation_pct": 10.0,
  "hold_duration_days": 3,
  "confidence_score": 0.75,
  "risk_reward_ratio": 2.0,
  "investment_amount": 9802.0,
  "technical_analysis": {
    "supertrend": {
      "trend": "bullish",
      "value": 2430.25
    },
    "adx": {
      "value": 28.5,
      "strength": "moderate"
    },
    "rsi": {
      "value": 65.2,
      "direction": "buy",
      "confidence": 0.6
    },
    "macd": {
      "value": {
        "macd": 12.5,
        "signal": 10.2,
        "histogram": 2.3
      },
      "direction": "buy",
      "confidence": 0.7
    }
  },
  "volume_analysis": {
    "avg_volume": 1500000,
    "current_volume": 1800000,
    "volume_ratio": 1.2,
    "trend": "increasing"
  },
  "reasoning": "BUY signal generated based on technical analysis:\n- Supertrend indicates bullish trend\n- ADX shows moderate trend strength (28.5)\n- RSI is bullish (65.2)\n- MACD shows bullish momentum\n- Volume trend is increasing (ratio: 1.2)\n- Confidence score: 75.0%\n- Recommended hold duration: 3 days"
}
```

## Troubleshooting

### No Recommendations Generated

- Check if watchlist items are active
- Verify DhanHQ API credentials are configured
- Check logs for data fetching errors
- Ensure sufficient historical data is available (at least 50 candles)

### Low Confidence Scores

- Market conditions may not be favorable
- Indicators may not be aligned
- Volume may not be supporting the trend
- Consider adjusting minimum confidence threshold

### Scheduler Not Running

- Check if scheduler thread is alive: `SwingTrading::Scheduler.instance.running?`
- Check application logs for errors
- Verify market hours (scheduler runs continuously but may skip during closed hours)

## Telegram Bot Setup

### Step 1: Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/botfather)
2. Send `/newbot` command
3. Follow the instructions to name your bot
4. Copy the bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Step 2: Get Your Chat ID

**Option 1: Using @userinfobot**
1. Search for [@userinfobot](https://t.me/userinfobot) on Telegram
2. Start a conversation
3. It will show your chat ID (a number like `123456789`)

**Option 2: Using your bot**
1. Start a conversation with your bot
2. Send any message to your bot
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":123456789}` in the response

### Step 3: Configure Environment Variables

Add to your `.env` file or environment:
```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

### Step 4: Test Notification

You can test the notification by manually triggering an analysis:
```bash
curl -X POST http://localhost:3000/api/swing_trading/recommendations/analyze/1?type=swing
```

If a recommendation is generated with confidence ≥ 70%, you should receive a Telegram message.

## Notification Format

Telegram notifications include:
- 🟢/🔴 Direction indicator (Buy/Sell)
- ⚡/📈 Type indicator (Swing/Long-term)
- Trade details (Entry, SL, TP, Quantity, Investment, Allocation)
- Technical analysis summary (Supertrend, ADX, RSI, MACD)
- Volume analysis
- Confidence score
- Reasoning
- Analysis timestamp and expiration

## Future Enhancements

- Support for more technical indicators
- Backtesting capabilities
- Performance tracking and analytics
- Customizable risk parameters per stock
- Integration with order placement system
- Real-time price alerts
- Multiple Telegram chat support
- Custom notification thresholds
