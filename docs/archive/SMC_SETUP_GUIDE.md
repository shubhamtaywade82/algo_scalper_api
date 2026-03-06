# SMC (Smart Money Concepts) Setup & Usage Guide

Complete guide to setting up and using the SMC + AVRZ trading signal system.

---

## 📋 Prerequisites

Before setting up SMC, ensure you have:

1. **DhanHQ API credentials** (for market data)
   - `CLIENT_ID` or `DHAN_CLIENT_ID`
   - `ACCESS_TOKEN` or `DHAN_ACCESS_TOKEN`

2. **Redis** (for alert cooldown/session tracking)
   - Running Redis server
   - `REDIS_URL` environment variable (optional, defaults to `redis://127.0.0.1:6379/0`)

3. **Telegram Bot** (optional, for alerts)
   - Bot token from @BotFather
   - Chat ID from @userinfobot

---

## 🚀 Quick Setup

### 1. Environment Variables

Add to your `.env` file:

```bash
# DhanHQ API (Required)
CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token

# Redis (Required for alert cooldown)
REDIS_URL=redis://127.0.0.1:6379/0

# Telegram (Optional, for alerts)
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

### 2. Telegram Bot Setup (Optional)

If you want to receive SMC alerts via Telegram:

#### Step 1: Create Bot
1. Open Telegram, search for [@BotFather](https://t.me/BotFather)
2. Send `/newbot` command
3. Follow instructions to create your bot
4. Copy the bot token (format: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

#### Step 2: Get Chat ID
1. Search for [@userinfobot](https://t.me/userinfobot) on Telegram
2. Start a conversation - it will reply with your chat ID (numeric value)
3. Alternatively, send a message to your bot and visit:
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
   Look for `chat.id` in the response

#### Step 3: Add to .env
```bash
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=123456789
```

### 3. Configuration (`config/algo.yml`)

SMC settings are already configured. Key settings:

```yaml
telegram:
  enabled: true  # Set to false to disable Telegram alerts
  smc_alert_cooldown_minutes: 30  # Cooldown between duplicate alerts
  smc_max_alerts_per_session: 2   # Max alerts per instrument per session

ai:
  enabled: true  # Enable AI analysis (requires Ollama or OpenAI)
```

---

## 📖 Usage Methods

### Method 1: Rails Console (Recommended for Testing)

#### Start Console
```bash
bin/rails console
```

#### Load Helpers
```ruby
# Load helper functions for easier candle fetching
load 'lib/console/smc_helpers.rb'

# Or use the example script for NIFTY/SENSEX
load 'lib/console/smc_example.rb'
fetch_nifty_and_sensex_candles
```

#### Basic Usage

```ruby
# 1. Get an instrument
instrument = Instrument.find_by_sid_and_segment(
  security_id: "13",      # NIFTY
  segment_code: "IDX_I"
)

# 2. Get SMC decision
engine = Smc::BiasEngine.new(instrument)
decision = engine.decision
# => :call, :put, or :no_trade

# 3. Get detailed analysis
details = engine.details
# => {
#   decision: :call,
#   timeframes: {
#     htf: { interval: "60", context: {...} },
#     mtf: { interval: "15", context: {...} },
#     ltf: { interval: "5", context: {...}, avrz: {...} }
#   }
# }

# 4. Get AI analysis (if enabled)
ai_analysis = engine.analyze_with_ai
# => AI-generated market analysis string
```

#### Advanced: Individual Detectors

```ruby
# Get candle series
series = instrument.candles(interval: "5")

# Create SMC context
context = Smc::Context.new(series)

# Access individual detectors
context.internal_structure.trend    # :bullish, :bearish, :range
context.swing_structure.trend      # Higher TF control
context.liquidity.sweep_direction   # :buy_side, :sell_side, nil
context.order_blocks.bullish       # Latest bullish OB candle
context.fvg.gaps                     # Array of FVG gaps
context.pd.premium?                 # true/false
context.pd.discount?                # true/false

# Serialize to hash
context.to_h
```

---

### Method 2: API Endpoint

#### Basic Decision
```bash
curl "http://localhost:3000/api/smc/decision?security_id=13&segment=IDX_I"
```

Response:
```json
{
  "ok": true,
  "decision": "call"
}
```

#### Detailed Analysis
```bash
curl "http://localhost:3000/api/smc/decision?security_id=13&segment=IDX_I&details=1"
```

Response includes full SMC context for HTF, MTF, and LTF timeframes.

#### With AI Analysis
```bash
curl "http://localhost:3000/api/smc/decision?security_id=13&segment=IDX_I&details=1&ai=1"
```

Response includes AI-generated market analysis.

#### From Rails Console
```ruby
# Using app.get (Rails test helper)
app.get("/api/smc/decision?security_id=13&segment=IDX_I&details=1")
response = JSON.parse(app.response.body)
```

---

### Method 3: Automatic Alerts (Production)

The system automatically sends Telegram alerts when:

1. **HTF bias is valid** (premium/discount zone)
2. **MTF aligns** (structure matches HTF)
3. **LTF entry conditions met**:
   - Liquidity sweep detected
   - AVRZ rejection confirmed
   - Structure break (CHoCH)

#### Alert Format

```
🚨 *SMC + AVRZ SIGNAL*

📌 *Instrument*: NIFTY
📊 *Action*: CALL
⏱ *Timeframe*: 5m
💰 *Spot Price*: 25000.0

🧠 *Confluence*:
• HTF in Discount (Demand)
• 15m CHoCH detected
• Liquidity sweep on 5m (sell_side)
• AVRZ rejection confirmed

🕒 *Time*: 02 Jan 2026, 12:30
```

#### Alert Cooldown & Limits

- **Cooldown**: 30 minutes between duplicate alerts (same instrument+decision)
- **Max per session**: 2 alerts per instrument per trading day
- **Duplicate suppression**: Alerts at similar price levels (<0.1% difference) are suppressed

---

## 🧪 Testing the System

### Test 1: Basic Decision
```ruby
# In Rails console
instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
engine = Smc::BiasEngine.new(instrument)
puts engine.decision
```

### Test 2: Detailed Analysis
```ruby
details = engine.details
puts JSON.pretty_generate(details)
```

### Test 3: Telegram Alert (Manual)
```ruby
# Create a test signal
signal = Smc::SignalEvent.new(
  instrument: instrument,
  decision: :call,
  timeframe: '5m',
  price: 25000.0,
  reasons: ['HTF in Discount', '15m CHoCH', 'Liquidity sweep', 'AVRZ rejection']
)

# Send alert
Notifications::Telegram::SmcAlert.new(signal).notify!
```

### Test 4: Verify Configuration
```ruby
# Check Telegram is enabled
AlgoConfig.fetch.dig(:telegram, :enabled)
# => true

# Check environment variables
ENV['TELEGRAM_BOT_TOKEN'].present?
ENV['TELEGRAM_CHAT_ID'].present?
```

---

## 🔧 Troubleshooting

### Issue: No alerts received

**Check 1: Telegram Configuration**
```ruby
# In Rails console
AlgoConfig.fetch.dig(:telegram, :enabled)  # Should be true
ENV['TELEGRAM_BOT_TOKEN'].present?        # Should be true
ENV['TELEGRAM_CHAT_ID'].present?          # Should be true
```

**Check 2: Redis Connection**
```ruby
# In Rails console
Rails.cache.write('test', 'value')
Rails.cache.read('test')  # Should return 'value'
```

**Check 3: Alert Cooldown**
```ruby
# Check if cooldown is active
Rails.cache.read('smc:alert:NIFTY:call')
# If present, cooldown is active
```

**Check 4: Logs**
```bash
# Check for errors
tail -f log/development.log | grep -i "smc\|telegram"
```

### Issue: "Instrument not found"

**Solution**: Verify instrument exists:
```ruby
Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
```

Common instruments:
- NIFTY: `security_id: "13", segment: "IDX_I"`
- BANKNIFTY: `security_id: "25", segment: "IDX_I"`
- SENSEX: `security_id: "51", segment: "IDX_I"`

### Issue: Insufficient candles

**Solution**: Use helper function to fetch with history:
```ruby
load 'lib/console/smc_helpers.rb'

instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
series = fetch_candles_with_history(instrument, interval: "60", target_candles: 60)
```

### Issue: AI analysis not working

**Check 1: AI Enabled**
```ruby
AlgoConfig.fetch.dig(:ai, :enabled)  # Should be true
```

**Check 2: Ollama Running** (if using Ollama)
```bash
curl http://localhost:11434/api/tags
```

**Check 3: Model Available**
```ruby
Services::Ai::OpenaiClient.instance.enabled?
```

---

## 📊 Understanding SMC Decisions

### Decision Logic

The system makes decisions based on:

1. **HTF (1H) Bias**: Premium/Discount zone
   - `:call` bias when in Discount (Demand zone)
   - `:put` bias when in Premium (Supply zone)

2. **MTF (15m) Alignment**: Structure must align with HTF
   - Structure trend matches HTF, OR
   - CHoCH detected (change of character)

3. **LTF (5m) Entry**: Liquidity + AVRZ confirmation
   - Liquidity sweep (buy-side or sell-side)
   - AVRZ rejection confirmed
   - Structure break (CHoCH)

### Decision Outcomes

- `:call` - Bullish signal (expect upward movement)
- `:put` - Bearish signal (expect downward movement)
- `:no_trade` - No valid signal (conditions not met)

---

## 🎯 Best Practices

1. **Use in Production**: Enable alerts only during market hours (9:15 AM - 3:30 PM IST)

2. **Monitor Cooldown**: Adjust `smc_alert_cooldown_minutes` in `config/algo.yml` based on your trading style

3. **Session Limits**: Adjust `smc_max_alerts_per_session` to prevent overtrading

4. **Combine with Risk Management**: SMC signals are entry signals - always use stop loss and position sizing

5. **Backtest First**: Test signals on historical data before live trading

---

## 📚 Additional Resources

- **Rails Console Usage**: See `docs/SMC_RAILS_CONSOLE_USAGE.md`
- **Telegram Setup**: See `docs/TELEGRAM_NOTIFICATIONS.md`
- **API Documentation**: See `app/controllers/smc_controller.rb`

---

## 🆘 Support

If you encounter issues:

1. Check logs: `tail -f log/development.log`
2. Verify configuration: `bin/rails runner "puts AlgoConfig.fetch.to_yaml"`
3. Test components individually (see Testing section above)

---

**Ready to trade!** 🚀

