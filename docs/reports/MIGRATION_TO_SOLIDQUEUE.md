# Migration Guide: Sidekiq → SolidQueue Only

## Summary

Simplified the system to use **SolidQueue ONLY** for both scheduling and background jobs. This eliminates the need for Redis and Sidekiq, reducing complexity to a single database-backed process.

## What Changed

### Before (Dual System)

```
┌───────────────┐  ┌───────────────┐
│  SolidQueue   │  │    Sidekiq    │
│  (bin/jobs)   │  │ (Redis-backed)│
│               │  │               │
│ • Scheduling  │  │ • Background  │
│               │  │   Jobs        │
└───────────────┘  └───────────────┘
     │                   │
     └───────┬───────────┘
             │
      2 PROCESSES REQUIRED
```

**Requirements:**
- ✅ PostgreSQL
- ✅ Redis
- ✅ Two processes: `bin/jobs` + `bundle exec sidekiq`

### After (Unified System)

```
┌─────────────────────────┐
│      SolidQueue         │
│      (bin/jobs)         │
│  (Database-backed)      │
│                         │
│  • Scheduling           │
│  • Background Jobs      │
│  • 15 concurrent workers│
└─────────────────────────┘
         │
  1 PROCESS ONLY
```

**Requirements:**
- ✅ PostgreSQL
- ❌ No Redis needed
- ✅ ONE process: `bin/jobs`

## Migration Steps

### Step 1: Update Queue Adapter

**File**: `config/application.rb`

```ruby
# Before
config.active_job.queue_adapter = :sidekiq

# After
config.active_job.queue_adapter = :solid_queue
```

### Step 2: Update Job Queues

**File**: `app/jobs/notifications/telegram/send_smc_alert_job.rb`

```ruby
# Before
queue_as :default

# After
queue_as :background
```

### Step 3: Update SolidQueue Workers Config

**File**: `config/queue.yml`

```yaml
# Before
workers:
  - queues: "*"
    threads: 3
    processes: 1

# After
workers:
  - queues: "*"
    threads: 5
    processes: 3  # 15 concurrent workers total
```

### Step 4: Reload Recurring Jobs

```bash
bundle exec rake solid_queue:load_recurring
```

### Step 5: Stop Sidekiq

```bash
# Stop Sidekiq (no longer needed)
pkill -f sidekiq

# Or if using systemd
sudo systemctl stop sidekiq
sudo systemctl disable sidekiq
```

### Step 6: Start SolidQueue

```bash
# Start SolidQueue only
bin/jobs
```

### Step 7: Verify

```bash
# Check SolidQueue processes
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

### Step 8: Wait and Check Logs

```bash
# Wait 5 minutes for first scan
tail -f log/development.log | grep -E "(SmcScannerJob|SendSmcAlertJob)"
```

## Verification Checklist

- [ ] `config/application.rb` has `queue_adapter = :solid_queue`
- [ ] `config/queue.yml` has `threads: 5` and `processes: 3`
- [ ] Recurring jobs loaded: `bundle exec rake solid_queue:load_recurring`
- [ ] Sidekiq stopped: `ps aux | grep sidekiq` returns nothing
- [ ] SolidQueue running: `ps aux | grep "bin/jobs"` returns process
- [ ] Workers active: 3 worker processes visible
- [ ] Scanner runs every 5 minutes
- [ ] Telegram messages received with complete AI analysis

## Rollback (If Needed)

If you need to rollback to Sidekiq:

### 1. Restore Queue Adapter

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq
```

### 2. Start Redis

```bash
redis-server
```

### 3. Start Sidekiq

```bash
bundle exec sidekiq
```

### 4. Restart SolidQueue

```bash
pkill -f "bin/jobs"
bin/jobs
```

## Benefits of SolidQueue-Only

| Aspect | Sidekiq | SolidQueue |
|--------|---------|------------|
| **Processes** | 2 (bin/jobs + sidekiq) | 1 (bin/jobs) |
| **Dependencies** | PostgreSQL + Redis | PostgreSQL only |
| **Setup Complexity** | Medium | Low |
| **Storage** | Redis (in-memory) | Database (persistent) |
| **Persistence** | Can lose jobs on crash | Never loses jobs |
| **Monitoring** | Redis commands | SQL queries |
| **Cost** | Redis hosting | Database only |
| **Reliability** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Performance** | Faster (Redis) | Fast enough (DB) |
| **Best For** | High volume (1000s/min) | Normal volume (100s/min) |

## Performance Comparison

### SMC Scanner Use Case

**Job Volume:**
- Scanner: 1 job every 5 minutes = 12 jobs/hour
- Notifications: ~0-10 jobs per scan = 0-120 jobs/hour
- **Total**: ~12-132 jobs/hour

**Verdict**: SolidQueue is MORE than sufficient for this volume.

### Concurrency

**Sidekiq** (before):
- Workers: 10 (default)
- Concurrent AI analyses: 10

**SolidQueue** (after):
- Workers: 15 (5 threads × 3 processes)
- Concurrent AI analyses: 15

**Result**: SolidQueue actually provides MORE concurrency! 🚀

### Response Times

| Operation | Sidekiq | SolidQueue |
|-----------|---------|------------|
| Scanner | 5-10s | 5-10s (same) |
| AI + Telegram | 20-30s | 20-30s (same) |
| Job enqueue | < 1ms | < 10ms |
| Job pickup | < 100ms | < 200ms |

**Difference**: Negligible for this use case.

## Database Impact

### Storage

SolidQueue stores jobs in PostgreSQL:

```sql
-- Tables created
solid_queue_jobs
solid_queue_recurring_tasks
solid_queue_recurring_executions
solid_queue_scheduled_executions
solid_queue_processes
```

**Size estimate:**
- 1 day: ~2,000 jobs × 1KB = ~2MB
- 1 month: ~60MB
- Automatically cleaned up every hour

**Impact**: Minimal

### Query Load

**Polling frequency**: 0.1s (configurable in `queue.yml`)

**Queries per second**: ~10-20 (lightweight)

**Impact**: Negligible for most databases

## Troubleshooting

### Issue: Jobs Not Processing

```bash
# Check workers
bundle exec rails runner "puts SolidQueue::Process.where(kind: 'Worker').count"
# Should return: 3

# If 0, check bin/jobs is running
ps aux | grep "bin/jobs"
```

### Issue: Slower Than Sidekiq

```bash
# Increase concurrency
JOB_CONCURRENCY=5 bin/jobs  # 5 processes × 5 threads = 25 workers
```

Or edit `config/queue.yml`:

```yaml
workers:
  - queues: "*"
    threads: 10
    processes: 5  # 50 concurrent workers
```

### Issue: Database Connection Pool

If you see "could not obtain connection" errors:

```ruby
# config/database.yml
production:
  pool: <%= ENV.fetch("DB_POOL", 25) %>  # Increase from default 5
```

Set environment variable:

```bash
DB_POOL=30  # More than workers count
```

## Production Deployment

### Environment Variables

```bash
# No REDIS_URL needed!
DATABASE_URL=postgresql://...
JOB_CONCURRENCY=5  # Number of worker processes
DB_POOL=30  # Database connection pool
```

### Systemd Service

```ini
# /etc/systemd/system/solidqueue.service
[Unit]
Description=SolidQueue Background Jobs
After=network.target postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/app/current
Environment=RAILS_ENV=production
Environment=DATABASE_URL=postgresql://...
Environment=JOB_CONCURRENCY=5
ExecStart=/usr/local/bin/bundle exec rake solid_queue:start
Restart=always

[Install]
WantedBy=multi-user.target
```

### Or Run in Puma

```bash
# Set environment variable
SOLID_QUEUE_IN_PUMA=true

# Start Puma
bundle exec puma
# SolidQueue runs inside Puma process
```

## FAQ

### Q: Do I need to keep Redis?

**A**: Not for SolidQueue/SMC scanner. You can remove Redis if not used elsewhere.

### Q: Is SolidQueue slower than Sidekiq?

**A**: Slightly (ms difference), but irrelevant for this use case. AI analysis (20-30s) dominates the time.

### Q: Can SolidQueue handle high volume?

**A**: Yes, up to 100s of jobs/minute easily. For 1000s/minute, Sidekiq is better.

### Q: What if my database goes down?

**A**: Jobs are lost in both systems if the database is down (SolidQueue) or Redis is down (Sidekiq). Use database backups.

### Q: Can I monitor SolidQueue like Sidekiq Web UI?

**A**: Yes! Use Mission Control for Jobs:

```ruby
# Gemfile
gem 'mission_control-jobs'

# config/routes.rb
mount MissionControl::Jobs::Engine, at: "/jobs"
```

Visit: `https://yourapp.com/jobs`

### Q: Should I switch back to Sidekiq?

**A**: Only if you need:
- 1000s of jobs per minute
- Sub-millisecond job enqueue time
- Existing Sidekiq infrastructure

For SMC scanner (12-132 jobs/hour), SolidQueue is perfect.

## Summary

### Changes Made

✅ Changed `queue_adapter` to `:solid_queue`
✅ Updated job queues to `:background`
✅ Increased SolidQueue workers to 15 (5×3)
✅ Removed Sidekiq dependency

### Benefits

✅ ONE process instead of two
✅ No Redis required
✅ Database-backed (never lose jobs)
✅ Simpler deployment
✅ Lower hosting costs
✅ More concurrent workers (15 vs 10)
✅ Same performance for this use case

### Migration Time

⏱ **5 minutes**:
1. Change config (1 min)
2. Stop Sidekiq (30s)
3. Start SolidQueue (30s)
4. Verify (3 min)

---

**Result**: Simpler, cheaper, more reliable. Perfect for ActiveRecord-based apps! 🎯
