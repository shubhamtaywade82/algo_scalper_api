# SMC Scanner - Complete Setup Guide

## 🚀 Quick Start (5 Minutes)

### Prerequisites

- ✅ Rails application with DhanHQ configured
- ✅ Telegram bot token and chat ID set
- ✅ OpenAI API key or Ollama configured

### Step 1: Load Recurring Jobs

```bash
bundle exec rake solid_queue:load_recurring
```

**Expected output:**
```
📋 Loading 3 recurring tasks for development environment...
  ✅ smc_scanner: every 5 minutes
  ✅ ai_technical_analysis_nifty: every 5 minutes
  ✅ ai_technical_analysis_sensex: every 5 minutes

✅ Done! 3 recurring tasks loaded.
   Restart bin/jobs for the dispatcher to pick them up.
```

### Step 2: Start SolidQueue

**One process handles everything:**
```bash
bin/jobs
```

**Or use bin/dev:**
```bash
./bin/dev
```

That's it! SolidQueue handles both scheduling AND background jobs (database-backed).

### Step 3: Verify It's Working

**Wait 5 minutes**, then check logs:

```bash
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob|SolidQueue)"
```

**Expected output:**
```
[SmcScannerJob] Starting SMC scan...
[SmcScannerJob] Scanning 3 indices...
[Smc::BiasEngine] Enqueued alert job for NIFTY - call
[SmcScannerJob] NIFTY: call
[SmcScannerJob] Scan completed: 3 successful, 0 errors
[SendSmcAlertJob] Processing alert for NIFTY - call
[SendSmcAlertJob] Fetching AI analysis for NIFTY...
[SmcAlert] Sending alert for NIFTY - call (3245 chars)
[SendSmcAlertJob] Alert sent for NIFTY - call
```

**Check Telegram**: You should receive messages with complete AI analysis! 📱

## 📊 What You Get

### Automatic Scanning

- 🔄 **Runs every 5 minutes** during market hours
- 📈 **Scans all configured indices** (NIFTY, BANKNIFTY, SENSEX, etc.)
- 🎯 **Detects SMC + AVRZ signals** (call/put/no_trade)
- 🤖 **AI analysis included** (complete, no truncation)
- 📲 **Telegram notifications** with entry suggestions

### Telegram Messages

```
🚨 SMC + AVRZ SIGNAL

📌 Instrument: NIFTY
📊 Action: CALL
⏱ Timeframe: 5m
💰 Spot Price: 24500.50

🧠 Confluence:
• HTF in Discount (Demand)
• 15m CHoCH detected
• Liquidity sweep on 5m (sell-side)
• AVRZ rejection confirmed

📊 Option Strikes (Lot: 50):
ATM: 24500
CALL: 24500 (ATM) @ ₹120.50, 24550 (ATM+1) @ ₹95.25
PUT: 24500 (ATM) @ ₹110.75, 24450 (ATM-1) @ ₹85.50
💡 Suggested Qty: 50 (1 lot)

🤖 AI Analysis:
**Market Structure Summary**
[Complete AI analysis with market structure, liquidity,
premium/discount zones, order blocks, FVGs, trading
recommendations, and risk factors - FULL ANALYSIS]

🕒 Time: 04 Jan 2026, 14:30
```

## ⚙️ Configuration

### Change Schedule (e.g., Every 15 Minutes)

Edit `config/recurring.yml`:

```yaml
development:
  smc_scanner:
    schedule: every 15 minutes  # Change from "every 5 minutes"
```

Reload:
```bash
bundle exec rake solid_queue:load_recurring
pkill -f "bin/jobs" && bin/jobs
```

### Market Hours Only (Production)

```yaml
production:
  smc_scanner:
    schedule: every 5 minutes between 9:15am and 3:30pm on weekdays
```

### Customize Cooldown

Edit `config/algo.yml`:

```yaml
telegram:
  enabled: true
  smc_alert_cooldown_minutes: 30  # Wait 30 min between same signals
  smc_max_alerts_per_session: 2   # Max 2 alerts per day per instrument

ai:
  enabled: true
```

## 🧪 Testing

### Test Manual Scan

```bash
bundle exec rake smc:scan
```

**Should complete in 5-10 seconds** (vs 90-180s before async)

### Test Background Job

```bash
bundle exec rails runner "SmcScannerJob.perform_later"
```

### Check Queue

```bash
# Check if recurring task is loaded
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"

# Check recent executions
bundle exec rails runner "SolidQueue::RecurringExecution.where(task_key: 'smc_scanner').order(run_at: :desc).limit(3).each { |e| puts e.run_at }"
```

## 🐛 Troubleshooting

### No Scanner Logs After 5 Minutes

```bash
# 1. Check if bin/jobs is running
ps aux | grep "bin/jobs"

# 2. If not running, start it
bin/jobs

# 3. Check if recurring task loaded
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"

# 4. If nil, reload tasks
bundle exec rake solid_queue:load_recurring
```

### No Telegram Notifications

```bash
# 1. Check if bin/jobs is running
ps aux | grep "bin/jobs"

# 2. If not running, start it
bin/jobs

# 3. Check configuration
bundle exec rails runner "puts AlgoConfig.fetch.dig(:telegram, :enabled)"
bundle exec rails runner "puts AlgoConfig.fetch.dig(:ai, :enabled)"

# 4. Check environment variables
echo $TELEGRAM_BOT_TOKEN
echo $TELEGRAM_CHAT_ID
echo $OPENAI_API_KEY

# 5. Check pending jobs
bundle exec rails runner "puts \"Pending: #{SolidQueue::Job.pending.count}\""
```

### Still Seeing Truncated AI Analysis

```bash
# 1. Restart SolidQueue to load new code
pkill -f "bin/jobs"
bin/jobs

# 2. Clear pending jobs (if needed)
bundle exec rails runner "SolidQueue::Job.pending.destroy_all"

# 3. Wait for next scan cycle (5 minutes)
```

## 📁 File Structure

### New Files Created

```
app/jobs/
  └── smc_scanner_job.rb                      # Automatic scanner job
  └── notifications/telegram/
      └── send_smc_alert_job.rb               # Async notification job

docs/
  └── smc_scanner_async_notifications.md     # Architecture docs
  └── smc_scanner_scheduling.md              # Scheduling guide

config/
  └── recurring.yml                          # Schedule configuration (updated)
```

### Modified Files

```
app/services/smc/bias_engine.rb              # Async notifications
app/services/notifications/telegram/
  └── smc_alert.rb                           # No AI truncation
```

## 🎯 Benefits

| Feature | Before | After |
|---------|--------|-------|
| **Execution** | Manual only | Automatic every 5 min |
| **Scanner Speed** | 90-180s | 5-10s |
| **AI Analysis** | Truncated at 2000 chars | Complete (chunked if long) |
| **Notifications** | Sync (blocking) | Async (background) |
| **Concurrency** | None | Multiple jobs parallel |
| **Market Coverage** | Manual timing | Continuous monitoring |

## 📚 Documentation

- **Full Architecture**: `docs/smc_scanner_async_notifications.md`
- **Scheduling Guide**: `docs/smc_scanner_scheduling.md`
- **Implementation Checklist**: `IMPLEMENTATION_CHECKLIST.md`
- **PR Description**: `PR_DESCRIPTION_SHORT.md`

## 🎉 You're Done!

The SMC scanner is now:

✅ Running automatically every 5 minutes
✅ Sending complete AI analysis to Telegram
✅ Processing notifications in background
✅ Monitoring all configured indices
✅ Production-ready with error handling
✅ **ONE process** - SolidQueue only (database-backed, no Redis!)

Just keep `bin/jobs` running, and you'll receive Telegram alerts automatically! 🚀

---

## 🎯 System Architecture

**SolidQueue Only** (Database-backed with ActiveRecord):
- ✅ ONE process: `bin/jobs`
- ✅ Database-backed (PostgreSQL)
- ✅ No Redis required
- ✅ No Sidekiq required
- ✅ 15 concurrent workers (5 threads × 3 processes)
- ✅ Handles both scheduling AND background jobs

**Questions?** Check the docs or logs:
```bash
# All logs in one place
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob|SolidQueue)"

# Check SolidQueue health
bundle exec rails runner "SolidQueue::Process.all.each { |p| puts \"#{p.name} (#{p.kind})\" }"

# Check pending jobs
bundle exec rails runner "puts \"Pending: #{SolidQueue::Job.pending.count}\""
```

**Need Help?** 
- `SETUP_SOLIDQUEUE_ONLY.md` - Detailed SolidQueue guide
- `docs/smc_scanner_scheduling.md` - Scheduling configuration
