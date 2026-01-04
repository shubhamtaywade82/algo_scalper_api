# SMC Scanner Automatic Scheduling

## Overview

The SMC scanner can now run automatically at scheduled intervals using **SolidQueue recurring jobs**. This guide explains how to enable and configure automatic scanning.

## Quick Start

### 1. Load Recurring Jobs

```bash
bundle exec rake solid_queue:load_recurring
```

This loads the SMC scanner job to run **every 5 minutes** by default.

### 2. Start SolidQueue

```bash
# Terminal 1: SolidQueue (handles recurring jobs)
bin/jobs

# Terminal 2: Sidekiq (handles notification jobs)
bundle exec sidekiq
```

### 3. Verify Scanning

**Check if recurring task is loaded:**
```bash
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"
```

**Expected output:**
```
every 5 minutes
```

**Check logs** (wait 5 minutes after starting):
```bash
tail -f log/development.log | grep SmcScannerJob
```

**Expected output:**
```
[SmcScannerJob] Starting SMC scan...
[SmcScannerJob] Scanning 3 indices...
[SmcScannerJob] NIFTY: call
[SmcScannerJob] BANKNIFTY: no_trade
[SmcScannerJob] Scan completed: 3 successful, 0 errors
```

## Configuration

### Schedule Options

Edit `config/recurring.yml` to customize the schedule:

#### Every 5 Minutes (Default - Recommended)

```yaml
development:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 5 minutes
    queue_name: default
    priority: 10
    description: "SMC + AVRZ scanner - every 5 minutes"
```

**Best for**: Intraday trading, catching quick setups on LTF (5m timeframe)

#### Every 15 Minutes (Conservative)

```yaml
development:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 15 minutes  # Change this line
    queue_name: default
    priority: 10
    description: "SMC + AVRZ scanner - every 15 minutes"
```

**Best for**: Swing trading, reducing noise, lower API usage

#### Market Hours Only (9:15 AM - 3:30 PM)

```yaml
development:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 5 minutes between 9:15am and 3:30pm
    queue_name: default
    priority: 10
    description: "SMC + AVRZ scanner - market hours only"
```

**Best for**: Production, avoiding unnecessary scans outside market hours

#### Custom Schedules

SolidQueue supports natural language schedules:

```yaml
# Every 10 minutes
schedule: every 10 minutes

# Every 30 minutes
schedule: every 30 minutes

# Every hour
schedule: every hour

# Every hour at specific minute
schedule: every hour at minute 15

# Specific times
schedule: at 9:15am, 12:00pm, 3:15pm

# Range with interval
schedule: every 15 minutes between 9:00am and 3:30pm on weekdays
```

### After Changing Schedule

**1. Reload recurring jobs:**
```bash
bundle exec rake solid_queue:load_recurring
```

**2. Restart SolidQueue:**
```bash
pkill -f "bin/jobs"
bin/jobs
```

Changes take effect immediately after restart.

## Architecture

### How It Works

```
SolidQueue Scheduler (every 5 minutes)
  └─> SmcScannerJob.perform_later
      └─> Scan all indices (NIFTY, BANKNIFTY, etc.)
          ├─> NIFTY: BiasEngine → decision → enqueue SendSmcAlertJob
          ├─> BANKNIFTY: BiasEngine → decision → enqueue SendSmcAlertJob
          └─> SENSEX: BiasEngine → decision → enqueue SendSmcAlertJob

Sidekiq Workers (concurrent)
  ├─> SendSmcAlertJob (NIFTY) → Fetch AI → Send Telegram
  ├─> SendSmcAlertJob (BANKNIFTY) → Fetch AI → Send Telegram
  └─> SendSmcAlertJob (SENSEX) → Fetch AI → Send Telegram
```

### Components

| Component | Purpose | Process |
|-----------|---------|---------|
| **SolidQueue Scheduler** | Triggers jobs on schedule | `bin/jobs` |
| **SmcScannerJob** | Scans all indices | SolidQueue worker |
| **SendSmcAlertJob** | AI analysis + Telegram | Sidekiq worker |

### Job Flow

1. **SolidQueue Scheduler** (every 5 minutes)
   - Creates `SmcScannerJob` at scheduled time
   - Job goes into SolidQueue default queue

2. **SmcScannerJob Execution** (5-10 seconds)
   - Loads all indices from config
   - Creates `BiasEngine` for each instrument
   - Gets decision (call/put/no_trade)
   - Enqueues `SendSmcAlertJob` if signal detected

3. **SendSmcAlertJob Execution** (concurrent, 20-30 seconds each)
   - Fetches AI analysis asynchronously
   - Builds Telegram message
   - Sends notification (with auto-chunking)

## Performance

### Resource Usage

| Schedule | Scans/Day | API Calls/Day | Notifications/Day |
|----------|-----------|---------------|-------------------|
| Every 5 min | 78 (6.5 hours) | ~234 (3 per scan) | Varies (0-50) |
| Every 15 min | 26 (6.5 hours) | ~78 (3 per scan) | Varies (0-20) |

**Note**: Based on 6.5 hour market session (9:15 AM - 3:45 PM)

### Optimization Tips

1. **Market Hours Only**: Use schedule with time range
   ```yaml
   schedule: every 5 minutes between 9:15am and 3:30pm
   ```

2. **Increase Intervals**: For slower strategies
   ```yaml
   schedule: every 15 minutes
   ```

3. **Skip Pre-Market**: Start after 9:30 AM
   ```yaml
   schedule: every 5 minutes between 9:30am and 3:30pm
   ```

4. **Cooldown Configuration**: Prevent duplicate alerts
   ```yaml
   # config/algo.yml
   telegram:
     smc_alert_cooldown_minutes: 30  # Wait 30 min between same signals
     smc_max_alerts_per_session: 2   # Max 2 alerts per day per instrument
   ```

## Monitoring

### Check Recurring Jobs

```bash
# List all recurring tasks
bundle exec rails runner "SolidQueue::RecurringTask.all.each { |t| puts \"#{t.key}: #{t.schedule}\" }"
```

**Expected output:**
```
smc_scanner: every 5 minutes
ai_technical_analysis_nifty: every 5 minutes
ai_technical_analysis_sensex: every 5 minutes
```

### Check Recent Executions

```bash
# Last 5 executions of SMC scanner
bundle exec rails runner "SolidQueue::RecurringExecution.where(task_key: 'smc_scanner').order(run_at: :desc).limit(5).each { |e| puts \"#{e.run_at} - #{e.created_at}\" }"
```

### Check Job Queue

```bash
# Pending jobs
bundle exec rails runner "puts \"Pending: #{SolidQueue::Job.pending.count}\""

# Failed jobs
bundle exec rails runner "puts \"Failed: #{SolidQueue::Job.failed.count}\""
```

### Check Logs

```bash
# SolidQueue logs
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob)"

# Sidekiq logs
tail -f log/sidekiq.log | grep SendSmcAlertJob
```

## Troubleshooting

### Issue: Scanner Not Running

**Symptom**: No `[SmcScannerJob]` logs after 5+ minutes

**Solution**:
```bash
# 1. Check if recurring task is loaded
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"

# 2. If not loaded, load it
bundle exec rake solid_queue:load_recurring

# 3. Restart SolidQueue
pkill -f "bin/jobs"
bin/jobs

# 4. Wait 5 minutes and check logs
tail -f log/development.log | grep SmcScannerJob
```

### Issue: Jobs Enqueued But Not Executing

**Symptom**: `[SmcScannerJob]` logs appear but no `[SendSmcAlertJob]` in Sidekiq

**Solution**:
```bash
# Check if Sidekiq is running
ps aux | grep sidekiq

# If not running, start it
bundle exec sidekiq
```

### Issue: No Telegram Notifications

**Symptom**: Jobs execute but no messages received

**Possible causes**:
1. **Cooldown active**: Check `[SmcAlert] Cooldown active` in logs
2. **No trading signals**: Decision was `no_trade` (check `[SmcScannerJob] NIFTY: no_trade`)
3. **AI disabled**: Check `config/algo.yml` → `ai.enabled: true`
4. **Telegram disabled**: Check `config/algo.yml` → `telegram.enabled: true`

**Debug**:
```bash
# Check SmcAlert logs
tail -f log/sidekiq.log | grep SmcAlert

# Check configuration
bundle exec rails runner "puts AlgoConfig.fetch.dig(:telegram, :enabled)"
bundle exec rails runner "puts AlgoConfig.fetch.dig(:ai, :enabled)"
```

### Issue: Rate Limit Errors

**Symptom**: `DhanHQ::RateLimitError` in logs

**Solution**:
```yaml
# Increase schedule interval to reduce API calls
development:
  smc_scanner:
    schedule: every 10 minutes  # or 15 minutes
```

### Issue: SolidQueue Process Died

**Symptom**: No logs at all, no jobs executing

**Solution**:
```bash
# Check if bin/jobs is running
ps aux | grep "bin/jobs"

# If not running, start it
bin/jobs

# Or use bin/dev to start everything
./bin/dev
```

## Manual Execution

You can still run the scanner manually:

### Via Rake Task (Original)

```bash
bundle exec rake smc:scan
```

### Via Background Job (New)

```bash
bundle exec rails runner "SmcScannerJob.perform_later"
```

### Synchronous (Testing)

```bash
bundle exec rails runner "SmcScannerJob.new.perform"
```

## Production Deployment

### Prerequisites

1. **SolidQueue configured** in `config/queue.yml`
2. **Recurring jobs loaded**:
   ```bash
   RAILS_ENV=production bundle exec rake solid_queue:load_recurring
   ```
3. **SolidQueue running**:
   ```bash
   # Option 1: Standalone
   bin/jobs

   # Option 2: In Puma (if SOLID_QUEUE_IN_PUMA=true)
   # Automatically starts with Puma
   ```
4. **Sidekiq running**:
   ```bash
   bundle exec sidekiq -e production -C config/sidekiq.yml
   ```

### Production Schedule Recommendation

```yaml
production:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 5 minutes between 9:15am and 3:30pm on weekdays
    queue_name: default
    priority: 10
    description: "SMC + AVRZ scanner - market hours only"
```

**Why**:
- ✅ Runs only during market hours (saves resources)
- ✅ Weekdays only (markets closed on weekends)
- ✅ Starts at 9:15 AM (market open)
- ✅ Ends at 3:30 PM (before market close at 3:30)
- ✅ Every 5 minutes (optimal for 5m LTF analysis)

### Monitoring Production

Use SolidQueue web UI (optional):

```ruby
# config/routes.rb
require 'mission_control/jobs/engine'

mount MissionControl::Jobs::Engine, at: "/jobs"
```

Access at: `https://your-app.com/jobs`

## FAQ

### Q: How do I change from 5 minutes to 15 minutes?

**A**: Edit `config/recurring.yml`:
```yaml
smc_scanner:
  schedule: every 15 minutes  # Change this
```

Then reload:
```bash
bundle exec rake solid_queue:load_recurring
pkill -f "bin/jobs" && bin/jobs
```

### Q: Can I run during pre-market (9:00-9:15 AM)?

**A**: Yes, adjust schedule:
```yaml
schedule: every 5 minutes between 9:00am and 3:30pm
```

### Q: How do I disable automatic scanning?

**A**: Option 1 - Remove from recurring.yml and reload
```bash
# Remove or comment out smc_scanner section in config/recurring.yml
bundle exec rake solid_queue:load_recurring
```

**A**: Option 2 - Delete from database
```bash
bundle exec rails runner "SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.destroy"
pkill -f "bin/jobs" && bin/jobs
```

### Q: Does this replace manual `rake smc:scan`?

**A**: No, you can still run manual scans anytime:
```bash
bundle exec rake smc:scan
```

Automatic scanning runs in addition to manual scans.

### Q: What's the difference between SmcScannerJob and rake smc:scan?

**A**: Functionally identical. The job wraps the rake task logic for background execution.

| Feature | Rake Task | Background Job |
|---------|-----------|----------------|
| Execution | Manual | Automatic (scheduled) |
| Process | Foreground | Background |
| Scheduling | None | SolidQueue |
| Use case | On-demand | Continuous monitoring |

## Summary

✅ **Automatic scanning enabled** via SolidQueue recurring jobs
✅ **Default schedule**: Every 5 minutes
✅ **Customizable**: Easy schedule changes in `config/recurring.yml`
✅ **Production-ready**: Market hours only, weekday support
✅ **Monitoring**: Logs, web UI, Rails console queries
✅ **Async notifications**: Background jobs with Sidekiq

To enable automatic scanning:
```bash
# 1. Load recurring jobs
bundle exec rake solid_queue:load_recurring

# 2. Start SolidQueue
bin/jobs

# 3. Start Sidekiq
bundle exec sidekiq

# Done! Scanner runs every 5 minutes automatically
```

---

**Last Updated**: January 4, 2026
**Version**: 1.0
