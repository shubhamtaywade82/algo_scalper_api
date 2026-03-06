# How to Run Recurring Jobs Automatically

## Quick Answer

**You need TWO processes running:**

1. **Web Server** (Rails/Puma): `./bin/dev` or `rails s`
2. **SolidQueue Worker** (for recurring jobs): `bin/jobs` (in a separate terminal)

`./bin/dev` alone does NOT start SolidQueue - you need to run `bin/jobs` separately.

---

## Step-by-Step Setup

### 1. Load Recurring Tasks (One-time setup)

First, load the recurring tasks from `config/recurring.yml` into the database:

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

### 2. Start Both Processes

You need **TWO terminals**:

#### Terminal 1: Web Server
```bash
./bin/dev
# OR
rails s
```

This starts:
- Rails web server (Puma)
- Trading services (MarketFeedHub, SignalScheduler, etc.)
- API endpoints

#### Terminal 2: SolidQueue Worker
```bash
bin/jobs
```

This starts:
- SolidQueue supervisor
- Scheduler (picks up recurring tasks)
- Workers (execute jobs)

---

## What Each Process Does

### `./bin/dev` (Web Server)
- ✅ Starts Rails/Puma web server
- ✅ Starts trading services (MarketFeedHub, SignalScheduler, RiskManager, etc.)
- ✅ Serves API endpoints
- ❌ **Does NOT run SolidQueue** (no recurring jobs)

### `bin/jobs` (SolidQueue Worker)
- ✅ Runs SolidQueue supervisor
- ✅ Scheduler picks up recurring tasks from database
- ✅ Workers execute enqueued jobs
- ✅ **This is what runs your recurring jobs!**

---

## Verification

### Check if Recurring Tasks are Loaded
```bash
bundle exec rails runner "puts SolidQueue::RecurringTask.all.map { |t| \"#{t.key}: #{t.schedule}\" }.join(\"\\n\")"
```

**Expected:**
```
smc_scanner: every 5 minutes
ai_technical_analysis_nifty: every 5 minutes
ai_technical_analysis_sensex: every 5 minutes
```

### Check if SolidQueue is Running
```bash
bundle exec rails runner "SolidQueue::Process.all.each { |p| puts \"#{p.name} (last_heartbeat: #{p.last_heartbeat_at})\" }"
```

**Expected:**
```
supervisor-xxxxx (last_heartbeat: 2025-12-22 ...)
dispatcher-xxxxx (last_heartbeat: 2025-12-22 ...)
worker-xxxxx (last_heartbeat: 2025-12-22 ...)
scheduler-xxxxx (last_heartbeat: 2025-12-22 ...)
```

### Check if Jobs are Being Created
```bash
bundle exec rails runner "SolidQueue::Job.order(created_at: :desc).limit(5).each { |j| puts \"#{j.class_name} - created: #{j.created_at}\" }"
```

### Check Logs
```bash
tail -f log/development.log | grep -E "(SmcScannerJob|AiTechnicalAnalysisJob)"
```

**Expected (every 5 minutes):**
```
[SmcScannerJob] Starting SMC scan...
[AiTechnicalAnalysisJob] Running analysis for NIFTY
[AiTechnicalAnalysisJob] Running analysis for SENSEX
```

---

## Common Issues

### Issue: Jobs Not Running

**Symptom**: No jobs in `SolidQueue::Job`, no logs

**Solution**:
1. Make sure `bin/jobs` is running (check with `ps aux | grep "bin/jobs"`)
2. Reload recurring tasks: `bundle exec rake solid_queue:load_recurring`
3. Restart `bin/jobs`: `pkill -f "bin/jobs" && bin/jobs`

### Issue: Scheduler Not Picking Up Tasks

**Symptom**: Tasks loaded but no recurring executions

**Solution**: Restart `bin/jobs` - scheduler only loads tasks at startup:
```bash
pkill -f "bin/jobs"
bin/jobs
```

### Issue: Only Web Server Running

**Symptom**: `./bin/dev` running but no jobs executing

**Solution**: Start `bin/jobs` in a separate terminal

---

## Production Setup

In production, you have two options:

### Option 1: Separate Process (Recommended)
```bash
# In systemd or process manager
bin/jobs
```

### Option 2: Inside Puma (Alternative)
Set environment variable:
```bash
SOLID_QUEUE_IN_PUMA=true rails s
```

This runs SolidQueue inside the Puma process (only in production when `SOLID_QUEUE_IN_PUMA=true`).

---

## Summary

**For recurring jobs to run automatically:**

1. ✅ Load recurring tasks: `bundle exec rake solid_queue:load_recurring`
2. ✅ Start web server: `./bin/dev` (Terminal 1)
3. ✅ Start SolidQueue: `bin/jobs` (Terminal 2)
4. ✅ Wait 5 minutes - jobs should start running automatically

**Both processes must be running for recurring jobs to work!**
