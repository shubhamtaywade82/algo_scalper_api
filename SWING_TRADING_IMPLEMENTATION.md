# Swing Trading & Long-Term Trading Implementation Summary

## Overview

This implementation adds automated swing trading and long-term trading notification capabilities to the algo scalper API bot. The system monitors selected stocks in the watchlist and provides buy/sell recommendations based on comprehensive technical analysis using DhanHQ APIs for OHLC and volume data.

## What Was Implemented

### 1. Database Schema

**Migration:** `db/migrate/20251206061825_create_swing_trading_recommendations.rb`
- Creates `swing_trading_recommendations` table
- Stores recommendations with entry, SL, TP, quantity, allocation, hold duration
- Includes technical analysis and volume analysis as JSONB fields
- Indexes for efficient querying

**Model:** `app/models/swing_trading_recommendation.rb`
- Full ActiveRecord model with validations
- Enums for recommendation_type, direction, status
- Helper methods for risk-reward ratio, investment amount, summaries

### 2. Core Services

**SwingTrading::Analyzer** (`app/services/swing_trading/analyzer.rb`)
- Analyzes watchlist stocks using multiple technical indicators
- Fetches intraday/historical OHLC data with volume from DhanHQ
- Calculates Supertrend, ADX, RSI, MACD indicators
- Performs volume analysis (comparing recent vs historical volumes)
- Generates comprehensive recommendations with:
  - Entry price, stop loss, take profit
  - Quantity and allocation percentage
  - Hold duration (3 days for swing, 15 days for long-term)
  - Confidence score (0.0 to 1.0)
  - Detailed reasoning

**SwingTrading::Scheduler** (`app/services/swing_trading/scheduler.rb`)
- Singleton service that runs every 15 minutes
- Monitors all active watchlist items (equity stocks)
- Generates both swing and long-term recommendations
- Avoids duplicate analysis (skips if analyzed within last hour)
- Sends notifications for new recommendations
- Updates existing recommendations if confidence improves

**SwingTrading::NotificationService** (`app/services/swing_trading/notification_service.rb`)
- Sends notifications via multiple channels:
  - API (default)
  - WebSocket (ActionCable broadcast)
  - Email (ActionMailer)

### 3. API Endpoints

**Watchlist Management** (`app/controllers/api/watchlist_controller.rb`)
- `GET /api/watchlist` - List all active watchlist items
- `POST /api/watchlist` - Add stock to watchlist
- `DELETE /api/watchlist/:id` - Remove stock from watchlist
- `GET /api/watchlist/:id` - Get watchlist item with recommendations

**Swing Trading Recommendations** (`app/controllers/api/swing_trading_recommendations_controller.rb`)
- `GET /api/swing_trading/recommendations` - List recommendations with filters
- `GET /api/swing_trading/recommendations/:id` - Get detailed recommendation
- `POST /api/swing_trading/recommendations/:id/execute` - Mark as executed
- `POST /api/swing_trading/recommendations/:id/cancel` - Cancel recommendation
- `POST /api/swing_trading/recommendations/analyze/:watchlist_item_id` - Manual analysis

### 4. Routes

Updated `config/routes.rb` with:
- Watchlist resource routes
- Swing trading recommendations namespace with nested routes

### 5. Email Notifications

**Mailer:** `app/mailers/swing_trading_mailer.rb`
- Sends email notifications for new recommendations

**View:** `app/views/swing_trading_mailer/recommendation_notification.html.erb`
- HTML email template with all recommendation details

### 6. Rake Tasks

**lib/tasks/swing_trading.rake**
- `rake swing_trading:start_scheduler` - Start the scheduler
- `rake swing_trading:analyze_watchlist` - Manually analyze all watchlist items
- `rake swing_trading:list_recommendations` - List active recommendations
- `rake swing_trading:expire_recommendations` - Expire old recommendations

### 7. Documentation

- `docs/SWING_TRADING.md` - Comprehensive documentation
- `SWING_TRADING_IMPLEMENTATION.md` - This summary

## Technical Analysis Details

### Indicators Used

1. **Supertrend** (Period: 10, Multiplier: 3.0)
   - Determines overall trend direction (bullish/bearish)

2. **ADX** (Period: 14)
   - Measures trend strength
   - Values: <20 (weak), 20-40 (moderate), 40-60 (strong), >60 (very strong)

3. **RSI** (Period: 14)
   - Oversold: <30 (bullish signal)
   - Overbought: >70 (bearish signal)

4. **MACD** (Fast: 12, Slow: 26, Signal: 9)
   - Bullish when MACD line crosses above signal line
   - Bearish when MACD line crosses below signal line

### Volume Analysis

- Compares recent average volume (last 20 candles) with historical average (previous 50 candles)
- Identifies increasing, decreasing, or stable volume trends
- Higher volume on breakouts increases confidence

### Signal Generation Logic

Signals are generated when:
- Supertrend indicates clear trend direction
- ADX shows strong trend strength (≥20)
- RSI and/or MACD confirm the direction
- Volume analysis supports the trend

Confidence score calculation:
- Base confidence: 0.5
- ADX strength factor: 0-0.2
- RSI confidence factor: 0-0.15
- MACD confidence factor: 0-0.15
- Volume confirmation factor: 0-0.1
- Total capped at 1.0

### Risk Parameters

- **Stop Loss**: 3% from entry price
- **Take Profit**: 6% from entry price (2:1 risk-reward ratio)
- **Minimum Confidence**: 0.6 (60%)
- **Hold Duration**: 3 days (swing), 15 days (long-term)

### Allocation Logic

- Base allocation: 10% (swing), 5% (long-term)
- Adjusted by confidence score multiplier
- Maximum: 20% (swing), 15% (long-term)
- Uses Capital::Allocator for available capital calculation

## Usage Examples

### 1. Add Stock to Watchlist

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

### 2. Start Scheduler

```bash
rake swing_trading:start_scheduler
```

Or add to application initialization:

```ruby
# config/initializers/swing_trading.rb
if Rails.env.production? || Rails.env.development?
  SwingTrading::Scheduler.instance.start
end
```

### 3. View Recommendations

```bash
curl http://localhost:3000/api/swing_trading/recommendations
```

### 4. Manual Analysis

```bash
curl -X POST http://localhost:3000/api/swing_trading/recommendations/analyze/1?type=swing
```

## Data Flow

1. **Scheduler** runs every 15 minutes
2. Fetches active watchlist items (equity stocks)
3. For each item, calls **Analyzer** service
4. **Analyzer**:
   - Fetches OHLC data with volume from DhanHQ
   - Calculates technical indicators
   - Performs volume analysis
   - Generates recommendation if confidence ≥ 0.6
5. **Scheduler** creates/updates recommendation in database
6. **NotificationService** sends notifications via configured channels
7. Recommendations accessible via API endpoints

## Key Features

✅ **Automated Analysis**: Runs continuously, analyzing watchlist stocks
✅ **Multi-Indicator Analysis**: Uses Supertrend, ADX, RSI, MACD
✅ **Volume Analysis**: Leverages volume data from DhanHQ APIs
✅ **Comprehensive Recommendations**: Entry, SL, TP, quantity, allocation, hold duration
✅ **Risk Management**: Calculates risk-reward ratios and allocation percentages
✅ **Confidence Scoring**: Provides confidence scores for each recommendation
✅ **Detailed Reasoning**: Human-readable explanations for each recommendation
✅ **Multiple Timeframes**: Supports both swing (15min) and long-term (1hr) analysis
✅ **Notifications**: API, WebSocket, and email support
✅ **RESTful API**: Full CRUD operations for watchlist and recommendations

## Next Steps

1. **Run Migration**:
   ```bash
   rails db:migrate
   ```

2. **Add Stocks to Watchlist**:
   Use the API endpoints or directly create WatchlistItem records

3. **Start Scheduler**:
   ```bash
   rake swing_trading:start_scheduler
   ```

4. **Monitor Recommendations**:
   Use API endpoints or rake task to view recommendations

5. **Configure Notifications** (Optional):
   - Set `SWING_TRADING_NOTIFICATION_EMAIL` environment variable for email
   - Configure ActionCable for WebSocket notifications

## Files Created/Modified

### New Files
- `db/migrate/20251206061825_create_swing_trading_recommendations.rb`
- `app/models/swing_trading_recommendation.rb`
- `app/services/swing_trading/analyzer.rb`
- `app/services/swing_trading/scheduler.rb`
- `app/services/swing_trading/notification_service.rb`
- `app/controllers/api/watchlist_controller.rb`
- `app/controllers/api/swing_trading_recommendations_controller.rb`
- `app/mailers/swing_trading_mailer.rb`
- `app/views/swing_trading_mailer/recommendation_notification.html.erb`
- `lib/tasks/swing_trading.rake`
- `docs/SWING_TRADING.md`
- `SWING_TRADING_IMPLEMENTATION.md`

### Modified Files
- `config/routes.rb` - Added new routes

## Testing Recommendations

1. Add a few stocks to watchlist
2. Run manual analysis: `rake swing_trading:analyze_watchlist`
3. Check recommendations: `rake swing_trading:list_recommendations`
4. Start scheduler and monitor logs
5. Test API endpoints with curl or Postman

## Notes

- The system uses DhanHQ APIs for OHLC and volume data
- All analysis is based on technical indicators - no fundamental analysis
- Recommendations expire after the hold duration period
- The scheduler runs continuously but may skip analysis during market closed hours
- Confidence scores help filter low-probability trades
- Volume analysis helps identify high-probability entries
