# SMC Scanner with Automatic Scheduling

## 🚀 Quick Start

### Setup (2 Commands)

```bash
# 1. Load recurring jobs
bundle exec rake solid_queue:load_recurring

# 2. Start SolidQueue
bin/jobs
```

**Done!** Scanner runs automatically every 5 minutes, sending complete AI analysis to Telegram.

## 📖 Documentation

### Getting Started
- **[SETUP_SOLIDQUEUE_ONLY.md](SETUP_SOLIDQUEUE_ONLY.md)** ← **START HERE**
- **[SMC_SCANNER_SETUP.md](SMC_SCANNER_SETUP.md)** - Quick setup guide

### Implementation Details
- **[FINAL_IMPLEMENTATION_SUMMARY.md](FINAL_IMPLEMENTATION_SUMMARY.md)** - Complete overview
- **[docs/smc_scanner_async_notifications.md](docs/smc_scanner_async_notifications.md)** - Architecture
- **[docs/smc_scanner_scheduling.md](docs/smc_scanner_scheduling.md)** - Scheduling

### Migration
- **[MIGRATION_TO_SOLIDQUEUE.md](MIGRATION_TO_SOLIDQUEUE.md)** - From Sidekiq to SolidQueue

## 🎯 What This Does

### Automatic Features

✅ **Runs every 5 minutes** (configurable)
✅ **Scans all indices** (NIFTY, BANKNIFTY, SENSEX)
✅ **SMC + AVRZ analysis** (call/put/no_trade signals)
✅ **AI-powered insights** (complete analysis, no truncation)
✅ **Telegram notifications** (with strikes, premiums, entry suggestions)
✅ **Background processing** (non-blocking, concurrent)

### System Architecture

```
SolidQueue (ONE process: bin/jobs)
  ├─> Scheduler: Triggers every 5 minutes
  ├─> SmcScannerJob: Scans indices (5-10s)
  └─> SendSmcAlertJob: AI + Telegram (20-30s, parallel)
```

**Database-backed** (PostgreSQL only, no Redis needed)

## 📱 Telegram Message Example

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
[COMPLETE AI ANALYSIS - NO TRUNCATION]
Market Structure Summary...
Liquidity Assessment...
Premium/Discount Analysis...
[... full analysis continues ...]

🕒 Time: 04 Jan 2026, 14:30
```

## ⚙️ Configuration

### Change Schedule

Edit `config/recurring.yml`:

```yaml
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
smc_scanner:
  schedule: every 5 minutes between 9:15am and 3:30pm on weekdays
```

### Cooldown Settings

Edit `config/algo.yml`:

```yaml
telegram:
  smc_alert_cooldown_minutes: 30  # Wait between duplicate alerts
  smc_max_alerts_per_session: 2   # Max alerts per day per instrument
```

## ✅ Verification

### Check Recurring Task

```bash
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"
```

Expected: `every 5 minutes`

### Check Logs

```bash
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob)"
```

### Check SolidQueue Health

```bash
bundle exec rails runner "SolidQueue::Process.all.each { |p| puts \"#{p.name} (#{p.kind})\" }"
```

## 🐛 Troubleshooting

### Scanner Not Running?

```bash
# Check if bin/jobs is running
ps aux | grep "bin/jobs"

# Start if not running
bin/jobs
```

### No Telegram Messages?

```bash
# Check configuration
bundle exec rails runner "puts AlgoConfig.fetch.dig(:telegram, :enabled)"
bundle exec rails runner "puts AlgoConfig.fetch.dig(:ai, :enabled)"

# Check environment variables
echo $TELEGRAM_BOT_TOKEN
echo $TELEGRAM_CHAT_ID
echo $OPENAI_API_KEY
```

### Jobs Pending But Not Processing?

```bash
# Check workers
bundle exec rails runner "puts \"Workers: #{SolidQueue::Process.where(kind: 'Worker').count}\""

# Should return: 3 (or your JOB_CONCURRENCY value)
```

## 📊 Performance

| Metric | Before | After |
|--------|--------|-------|
| Scanner duration | 90-180s | 5-10s |
| AI analysis | Blocking | Background |
| Message length | 2000 chars | Unlimited |
| Execution | Manual | Automatic (5 min) |
| Processes | 2 (SQ + Sidekiq) | 1 (SQ only) |
| Dependencies | PG + Redis | PG only |

## 🎯 Key Features

### 1. Complete AI Analysis
- No truncation at 2000 characters
- Automatic message chunking
- Multi-part messages if needed

### 2. Non-Blocking Scanner
- 10-20x faster (5-10s vs 90-180s)
- Background AI processing
- Concurrent job execution

### 3. Automatic Scheduling
- Runs every 5 minutes (configurable)
- Market hours only (production)
- No manual execution needed

### 4. SolidQueue Only
- ONE process (bin/jobs)
- Database-backed (PostgreSQL)
- No Redis required
- 15 concurrent workers

## 📚 Full Documentation

| Document | Description |
|----------|-------------|
| **[SETUP_SOLIDQUEUE_ONLY.md](SETUP_SOLIDQUEUE_ONLY.md)** | **Comprehensive setup guide** |
| **[SMC_SCANNER_SETUP.md](SMC_SCANNER_SETUP.md)** | Quick start guide |
| **[FINAL_IMPLEMENTATION_SUMMARY.md](FINAL_IMPLEMENTATION_SUMMARY.md)** | Complete implementation details |
| **[MIGRATION_TO_SOLIDQUEUE.md](MIGRATION_TO_SOLIDQUEUE.md)** | Migration from Sidekiq |
| **[docs/smc_scanner_async_notifications.md](docs/smc_scanner_async_notifications.md)** | Architecture & async flow |
| **[docs/smc_scanner_scheduling.md](docs/smc_scanner_scheduling.md)** | Scheduling configuration |

## 🚀 Production Deployment

```bash
# 1. Load recurring jobs
RAILS_ENV=production bundle exec rake solid_queue:load_recurring

# 2. Start SolidQueue
bin/jobs

# Or run in Puma
SOLID_QUEUE_IN_PUMA=true bundle exec puma
```

---

**Simple. Unified. Database-backed. Production-ready.** 🎯

**Get Started**: [SETUP_SOLIDQUEUE_ONLY.md](SETUP_SOLIDQUEUE_ONLY.md)
