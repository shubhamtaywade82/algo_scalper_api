# SMC Scanner - SolidQueue Only Setup (ActiveRecord-Based)

## Overview

This implementation uses **SolidQueue ONLY** for both scheduling and background processing. SolidQueue is database-backed (ActiveRecord), built into Rails 8, and requires only ONE process.

## Why SolidQueue Only?

✅ **Single System** - One process handles everything
✅ **Database-Backed** - Uses ActiveRecord (PostgreSQL)
✅ **No Redis** - No additional dependencies
✅ **Built into Rails 8** - No extra gems needed
✅ **Reliable** - Database persistence, no memory loss

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   SolidQueue (bin/jobs)                      │
│              Database-backed (ActiveRecord)                  │
│                                                              │
│  Scheduler:                                                  │
│    └─> Every 5 minutes: Trigger SmcScannerJob              │
│                                                              │
│  Workers (15 concurrent: 5 threads × 3 processes):          │
│    ├─> Queue: default → SmcScannerJob                      │
│    └─> Queue: background → SendSmcAlertJob (AI + Telegram) │
│                                                              │
│  All-in-one: Scheduling + Background Processing             │
└─────────────────────────────────────────────────────────────┘
```

## Quick Setup (1 Command!)

### Step 1: Load Recurring Jobs

```bash
bundle exec rake solid_queue:load_recurring
```

### Step 2: Start SolidQueue

```bash
bin/jobs
```

**That's it!** Only ONE process needed.

## Configuration

### Queue Adapter: `config/application.rb`

```ruby
config.active_job.queue_adapter = :solid_queue  # ✅ SolidQueue for all jobs
```

### Worker Configuration: `config/queue.yml`

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"          # Process all queues
      threads: 5           # 5 threads per process
      processes: 3         # 3 processes (total: 15 workers)
      polling_interval: 0.1
```

**Concurrency**: 5 threads × 3 processes = **15 concurrent workers**

### Recurring Schedule: `config/recurring.yml`

```yaml
development:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 5 minutes
    queue_name: default
    priority: 10

production:
  smc_scanner:
    class: SmcScannerJob
    schedule: every 5 minutes between 9:15am and 3:30pm on weekdays
    queue_name: default
    priority: 10
```

## How It Works

### 1. Scheduler (Built-in)

SolidQueue's scheduler triggers `SmcScannerJob` every 5 minutes:

```ruby
# Runs automatically
SmcScannerJob.perform_later  # Every 5 minutes
```

### 2. Scanner Job (Queue: default)

```ruby
class SmcScannerJob < ApplicationJob
  queue_as :default
  
  def perform
    # Scans all indices (NIFTY, BANKNIFTY, SENSEX)
    # Enqueues SendSmcAlertJob for each signal
  end
end
```

### 3. Notification Job (Queue: background)

```ruby
class SendSmcAlertJob < ApplicationJob
  queue_as :background
  
  def perform(instrument_id:, decision:, ...)
    # Fetch AI analysis (20-30s)
    # Send Telegram notification
  end
end
```

### 4. Workers Process Jobs

SolidQueue workers (15 concurrent) process jobs from both queues in parallel.

## Verification

### Check SolidQueue is Running

```bash
# Check process
ps aux | grep "bin/jobs"

# Check workers
bundle exec rails runner "SolidQueue::Process.all.each { |p| puts \"#{p.name} (#{p.kind})\" }"
```

**Expected output:**
```
scheduler-XXXX (Scheduler)
dispatcher-XXXX (Dispatcher)
worker-XXXX-1 (Worker)
worker-XXXX-2 (Worker)
worker-XXXX-3 (Worker)
```

### Check Recurring Tasks

```bash
bundle exec rails runner "SolidQueue::RecurringTask.all.each { |t| puts \"#{t.key}: #{t.schedule}\" }"
```

**Expected output:**
```
smc_scanner: every 5 minutes
ai_technical_analysis_nifty: every 5 minutes
ai_technical_analysis_sensex: every 5 minutes
```

### Check Job Execution

```bash
# Wait 5 minutes, then check recent jobs
bundle exec rails runner "SolidQueue::Job.order(created_at: :desc).limit(10).each { |j| puts \"#{j.class_name} - #{j.queue_name} - #{j.finished_at}\" }"
```

### Check Logs

```bash
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob|SolidQueue)"
```

**Expected output:**
```
[SmcScannerJob] Starting SMC scan...
[SmcScannerJob] Scanning 3 indices...
[Smc::BiasEngine] Enqueued alert job for NIFTY - call
[SmcScannerJob] Scan completed: 3 successful, 0 errors
[SendSmcAlertJob] Processing alert for NIFTY - call
[SendSmcAlertJob] Fetching AI analysis...
[SendSmcAlertJob] Alert sent for NIFTY - call
```

## Performance

### Concurrency

With 15 concurrent workers (5 threads × 3 processes):
- ✅ Scanner job: 5-10s
- ✅ Multiple AI analyses: Run in parallel
- ✅ Up to 15 jobs processing simultaneously

### Database Usage

SolidQueue stores jobs in PostgreSQL:

```sql
-- Check pending jobs
SELECT COUNT(*) FROM solid_queue_jobs WHERE finished_at IS NULL;

-- Check recent executions
SELECT * FROM solid_queue_recurring_executions 
WHERE task_key = 'smc_scanner' 
ORDER BY run_at DESC LIMIT 5;
```

### Adjusting Concurrency

Edit `config/queue.yml`:

```yaml
workers:
  - queues: "*"
    threads: 10          # More threads per process
    processes: 5         # More processes
    # Total: 10 × 5 = 50 concurrent workers
```

Or set environment variable:

```bash
JOB_CONCURRENCY=5 bin/jobs  # 5 processes × 5 threads = 25 workers
```

## Advantages vs Sidekiq

| Feature | SolidQueue | Sidekiq |
|---------|------------|---------|
| **Dependencies** | ✅ Built-in Rails 8 | ❌ Requires Redis |
| **Processes** | ✅ ONE (bin/jobs) | ❌ TWO (sidekiq + bin/jobs) |
| **Storage** | ✅ Database (ActiveRecord) | ❌ Redis (in-memory) |
| **Persistence** | ✅ Survives restarts | ⚠️ Redis data can be lost |
| **Scheduling** | ✅ Built-in recurring jobs | ❌ Needs sidekiq-cron gem |
| **Setup** | ✅ Zero config | ⚠️ Redis + Sidekiq config |
| **Job Inspection** | ✅ SQL queries | ⚠️ Redis commands |
| **Concurrency** | ✅ Good (15+ workers) | ✅ Excellent (100+ workers) |
| **Speed** | ✅ Fast (DB-backed) | ✅ Faster (Redis) |
| **Best For** | ✅ Most apps | ✅ High-volume apps |

**Recommendation**: SolidQueue is perfect for this use case (SMC scanner with AI analysis).

## Troubleshooting

### Issue: Scanner Not Running

```bash
# 1. Check bin/jobs is running
ps aux | grep "bin/jobs"

# 2. If not running, start it
bin/jobs

# 3. Check recurring tasks loaded
bundle exec rails runner "puts SolidQueue::RecurringTask.find_by(key: 'smc_scanner')&.schedule"

# 4. If nil, reload tasks
bundle exec rake solid_queue:load_recurring

# 5. Restart bin/jobs
pkill -f "bin/jobs" && bin/jobs
```

### Issue: Jobs Not Processing

```bash
# Check pending jobs
bundle exec rails runner "puts \"Pending: #{SolidQueue::Job.pending.count}\""

# Check workers
bundle exec rails runner "puts \"Workers: #{SolidQueue::Process.where(kind: 'Worker').count}\""

# Check failed jobs
bundle exec rails runner "SolidQueue::Job.failed.limit(5).each { |j| puts \"#{j.class_name}: #{j.error}\" }"
```

### Issue: Slow Performance

```bash
# Increase concurrency
JOB_CONCURRENCY=5 bin/jobs  # 5 processes instead of 3
```

Or edit `config/queue.yml`:

```yaml
workers:
  - queues: "*"
    threads: 10
    processes: 5
```

### Issue: Database Full

```bash
# Clean up finished jobs (runs automatically every hour)
bundle exec rails runner "SolidQueue::Job.clear_finished_in_batches"

# Or configure retention in recurring.yml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches"
    schedule: every hour
```

## Production Deployment

### 1. Load Recurring Jobs

```bash
RAILS_ENV=production bundle exec rake solid_queue:load_recurring
```

### 2. Start SolidQueue

**Option A: Standalone Process**

```bash
bin/jobs
```

**Option B: In Puma (Recommended)**

Set environment variable:

```bash
SOLID_QUEUE_IN_PUMA=true
```

SolidQueue will run inside Puma process (no separate bin/jobs needed).

### 3. Systemd Service (Production)

```ini
# /etc/systemd/system/solidqueue.service
[Unit]
Description=SolidQueue Background Jobs
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/app/current
Environment=RAILS_ENV=production
Environment=JOB_CONCURRENCY=5
ExecStart=/usr/local/bin/bundle exec rake solid_queue:start
Restart=always

[Install]
WantedBy=multi-user.target
```

Start service:

```bash
sudo systemctl enable solidqueue
sudo systemctl start solidqueue
sudo systemctl status solidqueue
```

## Monitoring

### Rails Console

```ruby
# Check scheduler health
SolidQueue::Process.where(kind: 'Scheduler').each do |p|
  puts "#{p.name}: last heartbeat #{Time.current - p.last_heartbeat_at}s ago"
end

# Check worker health
SolidQueue::Process.where(kind: 'Worker').count
# Should return: 3 (or JOB_CONCURRENCY value)

# Check recent jobs
SolidQueue::Job.order(created_at: :desc).limit(10).pluck(:class_name, :queue_name, :finished_at)

# Check failed jobs
SolidQueue::Job.failed.count
```

### Database Queries

```sql
-- Pending jobs by queue
SELECT queue_name, COUNT(*) 
FROM solid_queue_jobs 
WHERE finished_at IS NULL 
GROUP BY queue_name;

-- Recent recurring executions
SELECT task_key, run_at, created_at 
FROM solid_queue_recurring_executions 
ORDER BY run_at DESC 
LIMIT 10;

-- Job processing times
SELECT class_name, 
       AVG(EXTRACT(EPOCH FROM (finished_at - created_at))) as avg_seconds
FROM solid_queue_jobs 
WHERE finished_at IS NOT NULL 
GROUP BY class_name;
```

## Migration from Sidekiq

If you were using Sidekiq before:

### 1. Change Queue Adapter

```ruby
# config/application.rb
config.active_job.queue_adapter = :solid_queue  # Was :sidekiq
```

### 2. Stop Sidekiq

```bash
pkill -f sidekiq
```

### 3. Start SolidQueue

```bash
bin/jobs
```

### 4. Remove Sidekiq (Optional)

```ruby
# Gemfile
# gem 'sidekiq'  # Remove if not needed elsewhere
```

```bash
bundle install
```

**That's it!** Jobs automatically migrate to SolidQueue.

## Summary

### Setup (2 Steps)

```bash
# 1. Load recurring jobs
bundle exec rake solid_queue:load_recurring

# 2. Start SolidQueue
bin/jobs
```

### Key Benefits

✅ **ONE process** instead of two (bin/jobs replaces bin/jobs + sidekiq)
✅ **Database-backed** (ActiveRecord/PostgreSQL)
✅ **No Redis** required
✅ **Built into Rails 8**
✅ **15 concurrent workers** (configurable)
✅ **Automatic scheduling** (every 5 minutes)
✅ **Complete AI analysis** (no truncation)
✅ **Production-ready** (error handling, retries, monitoring)

### Requirements

- ✅ PostgreSQL database
- ✅ Rails 8 with SolidQueue
- ✅ ONE process: `bin/jobs`
- ❌ No Redis needed
- ❌ No Sidekiq needed

---

**Simple. Database-backed. One process. That's it.** 🚀
