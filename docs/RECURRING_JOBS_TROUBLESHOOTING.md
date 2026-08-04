# Recurring Jobs Troubleshooting Guide

## Issue: Recurring Jobs Not Running

### Symptoms
- Recurring tasks are loaded in the database (`SolidQueue::RecurringTask`)
- SolidQueue processes are running (supervisor, dispatcher, worker, scheduler)
- But no recurring executions are being created
- Jobs are not running every 5 minutes
- Telegram notifications are not being received

### Root Cause
Static recurring tasks in SolidQueue are only loaded when the scheduler process starts. When you update recurring tasks in the database, the scheduler doesn't automatically pick them up - it needs to be restarted.

### Solution

1. **Reload recurring tasks** (if you've updated `config/recurring.yml`):
   ```bash
   bundle exec rake solid_queue:load_recurring
   ```

2. **Restart the SolidQueue dispatcher** to pick up the changes:
   ```bash
   # If running bin/jobs separately, restart it
   # Kill the existing process and restart:
   pkill -f "bin/jobs" || pkill -f "solid_queue"
   bin/jobs
   ```

   Or if using `./bin/dev`:
   ```bash
   # Stop and restart
   ./bin/dev
   ```

### Verification

1. **Check if recurring tasks are loaded**:
   ```bash
   bundle exec rails runner "puts SolidQueue::RecurringTask.all.map { |t| \"#{t.key}: #{t.schedule}\" }.join(\"\\n\")"
   ```

2. **Check if SolidQueue processes are running**:
   ```bash
   bundle exec rails runner "SolidQueue::Process.all.each { |p| puts \"#{p.name} (last_heartbeat: #{p.last_heartbeat_at})\" }"
   ```

3. **Check if recurring executions are being created** (wait 1-2 minutes after restart):
   ```bash
   bundle exec rails runner "SolidQueue::RecurringExecution.order(run_at: :desc).limit(5).each { |e| puts \"#{e.task_key}: run_at=#{e.run_at}\" }"
   ```

4. **Check if jobs are being enqueued**:
   ```bash
   bundle exec rails runner "SolidQueue::Job.order(created_at: :desc).limit(10).each { |j| puts \"#{j.class_name} - #{j.created_at}\" }"
   ```

5. **Check job execution logs** in `log/development.log` for:
   ```
   [AiTechnicalAnalysisJob] Running analysis for NIFTY
   [AiTechnicalAnalysisJob] Running analysis for SENSEX
   ```

### Common Issues

#### Issue: Arguments Double-Encoded
**Symptom**: Jobs fail with argument parsing errors

**Fix**: The rake task has been fixed to pass arrays directly instead of JSON strings. Reload tasks:
```bash
bundle exec rake solid_queue:load_recurring
```

#### Issue: Scheduler Not Running
**Symptom**: No `scheduler-*` process in `SolidQueue::Process.all`

**Fix**: Make sure `bin/jobs` is running. The scheduler is part of the SolidQueue supervisor.

#### Issue: Jobs Not Executing
**Symptom**: Jobs are enqueued but not executing

**Fix**: Check if workers are running:
```bash
bundle exec rails runner "puts SolidQueue::Process.where('name LIKE ?', 'worker-%').count"
```

### Manual Testing

To test if the job works manually:
```bash
STREAM=true bundle exec rake 'ai:technical_analysis["OPTIONS buying intraday in INDEX like NIFTY"]'
```

If this works and sends Telegram notifications, but the recurring jobs don't, then the issue is with the scheduler not picking up the recurring tasks - restart `bin/jobs`.

### Configuration Files

- **Recurring tasks config**: `config/recurring.yml`
- **SolidQueue config**: `config/queue.yml`
- **Rake task**: `lib/tasks/solid_queue_recurring.rake`

### Notes

- In **development**, SolidQueue runs via `bin/jobs` (separate process)
- In **production**, SolidQueue can run in Puma if `SOLID_QUEUE_IN_PUMA=true`
- Static recurring tasks (`static: true`) are loaded at scheduler startup
- After updating recurring tasks, always restart the scheduler/dispatcher
