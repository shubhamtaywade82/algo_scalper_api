# SMC/AVRZ Usage & Integration Guide

## 📊 Current Status

**SMC/AVRZ is currently NOT automatically running.** It's available but needs to be triggered manually or integrated into the signal generation flow.

---

## 🔄 How It Currently Works

### Option 1: Manual Usage (Rails Console)

```ruby
# In Rails console
instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
engine = Smc::BiasEngine.new(instrument)

# Get decision (automatically sends Telegram alert if conditions met)
decision = engine.decision
# => :call, :put, or :no_trade

# Get detailed analysis
details = engine.details
```

**When does it send alerts?**
- Only when `decision` returns `:call` or `:put`
- Automatically sends Telegram alert via `notify()` method
- Respects cooldown and session limits

### Option 2: API Endpoint

```bash
# Basic decision
curl "http://localhost:3000/smc/decision?security_id=13&segment=IDX_I"

# With details
curl "http://localhost:3000/smc/decision?security_id=13&segment=IDX_I&details=1"

# With AI analysis
curl "http://localhost:3000/smc/decision?security_id=13&segment=IDX_I&details=1&ai=1"
```

**Note**: API calls do NOT automatically send Telegram alerts (only manual `decision` calls do).

### Option 3: Rake Task (Not Created Yet)

You could create a rake task to run SMC analysis periodically:

```ruby
# lib/tasks/smc_scanner.rake
namespace :smc do
  desc "Run SMC/AVRZ analysis for all configured indices"
  task scan: :environment do
    indices = IndexConfigLoader.load_indices
    indices.each do |idx_cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )
      next unless instrument

      engine = Smc::BiasEngine.new(instrument)
      decision = engine.decision # This will send Telegram alert if conditions met

      Rails.logger.info("[SMCSanner] #{idx_cfg[:key]}: #{decision}")
    end
  end
end
```

Then run:
```bash
bundle exec rake smc:scan
```

---

## 🚀 Integration Options

### Option A: Integrate into Signal::Scheduler (Recommended)

**Current Flow:**
```
Signal::Scheduler (every 30s)
  → Uses Supertrend + ADX
  → Generates signals
  → Triggers entry
```

**With SMC Integration:**
```
Signal::Scheduler (every 30s)
  → Check SMC/AVRZ first (as filter)
  → If SMC says :no_trade → skip
  → If SMC says :call/:put → use as signal
  → Then apply Supertrend/ADX confirmation (optional)
  → Trigger entry
```

**Implementation:**

Modify `app/services/signal/scheduler.rb`:

```ruby
def process_index(idx_cfg)
  # ... existing code ...

  # NEW: Check SMC/AVRZ first
  instrument = IndexInstrumentCache.instance.get_or_fetch(idx_cfg)
  return unless instrument

  smc_engine = Smc::BiasEngine.new(instrument)
  smc_decision = smc_engine.decision # This sends Telegram alert automatically

  # Skip if SMC says no trade
  if smc_decision == :no_trade
    Rails.logger.debug("[SignalScheduler] SMC filter: no_trade for #{idx_cfg[:key]}")
    return
  end

  # Use SMC decision as signal direction
  direction = smc_decision == :call ? :bullish : :bearish

  # Continue with existing entry logic...
  # (strike selection, entry guard, etc.)
end
```

### Option B: Separate SMC Scheduler Service

Create a dedicated service that runs SMC analysis:

```ruby
# app/services/smc/scheduler.rb
module Smc
  class Scheduler < TradingSystem::BaseService
    INTERVAL = 60 # Check every 60 seconds (5-minute candles)

    def start
      return if @running
      @running = true
      @thread = Thread.new { run_loop }
    end

    private

    def run_loop
      Thread.current.name = 'smc-scheduler'
      loop do
        break unless @running

        begin
          scan_indices if TradingSession::Service.market_open?
        rescue StandardError => e
          Rails.logger.error("[Smc::Scheduler] Error: #{e.class} - #{e.message}")
        end

        sleep INTERVAL
      end
    end

    def scan_indices
      indices = IndexConfigLoader.load_indices
      indices.each do |idx_cfg|
        instrument = Instrument.find_by_sid_and_segment(
          security_id: idx_cfg[:sid].to_s,
          segment_code: idx_cfg[:segment]
        )
        next unless instrument

        engine = BiasEngine.new(instrument)
        decision = engine.decision # Sends Telegram alert automatically

        Rails.logger.debug("[Smc::Scheduler] #{idx_cfg[:key]}: #{decision}")
      end
    end
  end
end
```

Then register in `config/initializers/trading_supervisor.rb`:

```ruby
supervisor.register(:smc_scheduler, Smc::Scheduler.new)
```

### Option C: Replace Signal::Scheduler with SMC

**Not recommended** - SMC is more conservative and will generate fewer signals. Better to use as a filter or confirmation.

---

## 📱 What to Expect

### When SMC Conditions Are Met

1. **Telegram Alert Sent** (if configured):
   ```
   🚨 *SMC + AVRZ SIGNAL*

   📌 *Instrument*: NIFTY
   📊 *Action*: CALL
   ⏱ *Timeframe*: 5m
   💰 *Spot Price*: 26328.55

   🧠 *Confluence*:
   • HTF in Discount (Demand)
   • 15m CHoCH detected
   • Liquidity sweep on 5m (sell_side)
   • AVRZ rejection confirmed

   📊 *Option Strikes*:
   ATM: 26350
   CALL: 26350 (ATM), 26400 (ATM+1)
   PUT: 26350 (ATM), 26300 (ATM-1)

   🕒 *Time*: 02 Jan 2026, 12:30
   ```

2. **Decision Returned**:
   - `:call` - Bullish signal (expect upward movement)
   - `:put` - Bearish signal (expect downward movement)
   - `:no_trade` - No valid signal (most common)

### Alert Frequency

- **Cooldown**: 30 minutes between duplicate alerts (same instrument+decision)
- **Max per session**: 2 alerts per instrument per trading day
- **Duplicate suppression**: Alerts at similar price levels (<0.1% difference) are suppressed

**Expected behavior:**
- On a good trading day: 1-3 alerts total (across all instruments)
- On a choppy day: 0 alerts (system correctly identifies no-trade conditions)
- This is **by design** - SMC only alerts when all conditions align

---

## 🎯 Recommended Setup

### For Manual Monitoring

1. **Keep Rails server running** (`bin/dev` or `rails s`)
2. **Set up Telegram** (bot token + chat ID)
3. **Run manual checks** in Rails console when you want to check signals
4. **Or use API endpoint** for external monitoring tools

### For Automatic Alerts

**Option 1: Rake Task with Cron** (Simple)

```bash
# Add to crontab (runs every 5 minutes during market hours)
*/5 9-15 * * 1-5 cd /path/to/app && bundle exec rake smc:scan
```

**Option 2: Integrate into Signal::Scheduler** (Recommended)

- SMC becomes a filter/confirmation layer
- Runs automatically every 30 seconds with other signals
- Sends alerts when conditions are met
- No additional setup needed

**Option 3: Separate SMC Scheduler Service** (Most Flexible)

- Dedicated service for SMC analysis
- Runs independently from other signal generation
- Can be configured with different intervals
- Requires adding to supervisor

---

## 🔍 Monitoring & Debugging

### Check if SMC is Working

```ruby
# In Rails console
instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
engine = Smc::BiasEngine.new(instrument)

# Check decision
engine.decision

# Check detailed analysis
details = engine.details
puts JSON.pretty_generate(details)

# Check if Telegram is configured
AlgoConfig.fetch.dig(:telegram, :enabled)
ENV['TELEGRAM_BOT_TOKEN'].present?
ENV['TELEGRAM_CHAT_ID'].present?
```

### View Logs

```bash
# Watch for SMC activity
tail -f log/development.log | grep -i "smc\|avrz"

# Watch for Telegram alerts
tail -f log/development.log | grep -i "smcalert\|telegram"
```

### Test Alert Manually

```ruby
# In Rails console
instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")
engine = Smc::BiasEngine.new(instrument)

# This will send alert if conditions are met
decision = engine.decision
```

---

## ⚠️ Important Notes

1. **SMC is Conservative**: It will return `:no_trade` most of the time. This is correct behavior - it only signals when all conditions align.

2. **Not Integrated Yet**: SMC is NOT automatically running. You need to either:
   - Call it manually
   - Integrate it into Signal::Scheduler
   - Create a separate scheduler service

3. **Telegram Alerts**: Only sent when `decision` returns `:call` or `:put`. API calls don't trigger alerts.

4. **Market Hours**: SMC works best during market hours (9:15 AM - 3:30 PM IST) when there's live data.

5. **Data Requirements**: Needs sufficient historical candles (60 for 1H, 100 for 15m, 150 for 5m). Use `fetch_candles_with_history` helper if needed.

---

## 🚀 Next Steps

1. **Test manually** first using Rails console
2. **Verify Telegram alerts** are working
3. **Choose integration method** (Option A, B, or C above)
4. **Monitor logs** to see when alerts fire
5. **Adjust cooldown/session limits** in `config/algo.yml` if needed

---

**The system is ready - it just needs to be triggered!** 🎯

