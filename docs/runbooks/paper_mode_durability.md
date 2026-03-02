# Paper-Mode Durability Runbook

**Location:** `docs/runbooks/paper_mode_durability.md`  
**Purpose:** Pre-live gate validation for LM1 (durable exit intent), LM2 (deterministic exit COID), and LM3 (startup reconciliation).  
**Must pass before:** Any deployment enabling `paper_trading.enabled: false` (live trading).  
**Estimated time:** 45–60 minutes including two kill/restart drill cycles.

---

## What This Validates

| ID | Risk | Validated By |
|----|------|-------------|
| LM1 | Process crash between broker call and `mark_exited!` creates orphaned open position | Stage 6 — kill `-9` drill, intent fields survive |
| LM2 | Non-deterministic exit COID on restart causes duplicate broker order | Stage 6 — same COID reused post-restart |
| LM3 | DB is stale ground truth at boot; risk loop evaluates phantom positions | Stage 7 — reconciliation log appears before services start |

---

## Prerequisites

All of the following must be true before starting.

```bash
# 1. Paper mode is active in algo config
grep "enabled" config/algo.yml | grep -A1 "paper_trading"
# Expected: enabled: true

# 2. Exit intent migration is applied
bin/rails db:migrate:status | grep 20260225090000
# Expected: up   20260225090000  Add exit intent fields to position trackers

# 3. Correct commits are present
git log --oneline -5
# Expected: fdd1146, e35346b, 68ee6ab, c14b415, e44d41c all visible

# 4. Gateway resolves to paper in current config
bin/rails runner "puts Orders.config.gateway.class.name"
# Expected: Orders::GatewayPaper

# 5. DB columns exist
bin/rails runner "
  cols = PositionTracker.column_names
  %w[exit_requested_at exit_coid exit_sent_at exit_order_id].each do |c|
    puts c + ': ' + (cols.include?(c) ? 'present' : 'MISSING')
  end
"
# Expected: all four columns present
```

**Do not proceed if any prerequisite fails.**

---

## Stage 1 — Clean Slate

Ensure no stale active positions from prior runs.

```bash
bin/rails runner "
  active = PositionTracker.where(status: 'active').count
  pending = PositionTracker.where(exit_requested_at: ..Time.current, status: 'active').count
  puts 'Active trackers:          ' + active.to_s
  puts 'Pending exit intent:      ' + pending.to_s
"
```

If active count is non-zero from a prior incomplete run, clear it:

```bash
# Only run if prior test data — do NOT run against production data
bin/rails runner "
  PositionTracker.where(order_no: PositionTracker.where(status: 'active')
    .where('order_no LIKE ?', 'PAPER-%').pluck(:order_no))
    .update_all(status: 'exited', exit_reason: 'runbook_cleanup')
  puts 'Cleaned up test paper trackers'
"
```

**Pass criterion:** Active count is `0` before proceeding to Stage 2.

---

## Stage 2 — Daemon Start and Reconciliation Verification (LM3)

```bash
# Start daemon with DhanHQ disabled — paper only, no live broker calls
PAPER_MODE=true DHANHQ_ENABLED=false ENABLE_TRADING_SERVICES=true \
  bundle exec rake trading:daemon &
DAEMON_PID=$!
echo "Daemon PID: $DAEMON_PID"

# Allow 10 seconds for boot sequence
sleep 10

# Verify reconciliation ran before risk manager
grep -E "Bootstrap|Reconciliation|PositionSync|TradingDaemon|risk_manager" \
  log/trading.log | tail -20
```

**Pass criteria:**
- `Bootstrap.*reconciliation` or `PositionSync.*force_sync` log line appears.
- It appears **before** any `risk_manager started` or `TradingDaemon Started` line.
- No `FATAL` or `reconciliation failed` lines.

**Fail condition:** Risk manager starts with no preceding reconciliation log line. Do not proceed — fix bootstrap wiring first.

---

## Stage 3 — Paper Entry

Trigger a signal cycle and observe entry creation.

```bash
# Watch entry logs in one terminal
tail -f log/trading.log | grep -E "EntryGuard|place_market|PAPER-|paper.*entry|Successfully"
```

In a second terminal, trigger the scheduler:

```bash
bin/rails runner "Signal::Scheduler.new.run_once rescue puts $!.message"
```

After entry fires, verify tracker fields:

```bash
bin/rails runner "
  t = PositionTracker.order(created_at: :desc).first
  puts 'order_no:          ' + t.order_no.to_s
  puts 'paper:             ' + t.paper.to_s
  puts 'status:            ' + t.status.to_s
  puts 'entry_price:       ' + t.entry_price.to_s
  puts 'exit_requested_at: ' + t.exit_requested_at.to_s
  puts 'exit_coid:         ' + t.exit_coid.to_s
"
```

**Pass criteria:**
- `order_no` begins with `PAPER-`.
- `paper: true`.
- `status: active`.
- `exit_requested_at: nil` (no premature exit intent).
- `exit_coid: nil`.

---

## Stage 4 — Normal Exit Path

Trigger exit via LTP manipulation to force stop-loss.

```bash
# Capture tracker ID for this run
TRACKER_ID=$(bin/rails runner "puts PositionTracker.where(status:'active').order(created_at: :desc).first&.id")
echo "Tracker ID: $TRACKER_ID"

# Push LTP 20% below entry to trigger stop loss
bin/rails runner "
  t = PositionTracker.find($TRACKER_ID)
  fake_ltp = (BigDecimal(t.entry_price.to_s) * 0.80).round(2)
  Live::TickCache.store(t.segment, t.security_id, fake_ltp)
  puts 'Pushed fake LTP: ' + fake_ltp.to_s + ' (entry was: ' + t.entry_price.to_s + ')'
"

# Watch for exit sequence
tail -f log/trading.log | grep -E "ExitEngine|exit_requested|prepare_exit|mark_exited|coid" &
LOG_PID=$!
sleep 30
kill $LOG_PID 2>/dev/null
```

Verify exit intent and ack fields:

```bash
bin/rails runner "
  t = PositionTracker.find($TRACKER_ID)
  puts 'status:            ' + t.status.to_s
  puts 'exit_requested_at: ' + t.exit_requested_at.to_s
  puts 'exit_coid:         ' + t.exit_coid.to_s
  puts 'exit_sent_at:      ' + t.exit_sent_at.to_s
  puts 'exit_order_id:     ' + t.exit_order_id.to_s
  puts 'exit_price:        ' + t.exit_price.to_s
  puts 'exit_reason:       ' + t.exit_reason.to_s
"
```

**Pass criteria:**
- `status: exited`.
- `exit_requested_at` present, timestamp before `exit_sent_at`.
- `exit_coid` present (deterministic value).
- `exit_sent_at` present, timestamp after `exit_requested_at`.
- `exit_price` non-zero, approximately matches fake LTP.

---

## Stage 5 — Kill -9 Durability Drill Preparation

**Run Stage 6 twice.** Concurrency bugs hide in timing.

Create a fresh active paper tracker by repeating Stage 3 and record tracker id:

```bash
bin/rails runner "
  t = PositionTracker.where(status: 'active').order(created_at: :desc).first
  puts 'Ready: ' + t.order_no.to_s + ' (id: ' + t.id.to_s + ')'
"
TRACKER_ID=<paste id from above>
```

Capture expected deterministic COID for this tracker:

```bash
bin/rails runner "
  require 'digest'
  t = PositionTracker.find($TRACKER_ID)
  raw = 'exit-' + t.id.to_s + '-' + t.entry_order_id.to_s
  expected = Digest::SHA256.hexdigest(raw).first(32)
  puts 'Expected exit_coid: ' + expected
"
EXPECTED_COID=<paste from above>
```

---

## Stage 6 — Kill -9 Durability Drill (LM1 + LM2)

Trigger exit and kill daemon immediately after intent logging.

```bash
# Push LTP to trigger stop loss
bin/rails runner "
  t = PositionTracker.find($TRACKER_ID)
  fake_ltp = (BigDecimal(t.entry_price.to_s) * 0.80).round(2)
  Live::TickCache.store(t.segment, t.security_id, fake_ltp)
"

# Watch logs — kill as soon as you see prepare/intent logs
tail -f log/trading.log | grep -E "exit_requested|prepare_exit|ExitEngine"
# In another terminal, immediately run:
kill -9 $DAEMON_PID
```

Verify durable intent survived crash:

```bash
bin/rails runner "
  t = PositionTracker.find($TRACKER_ID)
  puts 'status:            ' + t.status.to_s
  puts 'exit_requested_at: ' + t.exit_requested_at.to_s
  puts 'exit_coid:         ' + t.exit_coid.to_s
  puts 'exit_sent_at:      ' + t.exit_sent_at.to_s
"
```

**Pass criteria (post-crash, pre-restart):**
- `exit_requested_at` **present**.
- `exit_coid` **present** and matches `$EXPECTED_COID`.
- `status` may still be `active` (acceptable).
- `exit_sent_at` may be nil (acceptable, timing dependent).

Restart and verify COID reuse:

```bash
PAPER_MODE=true DHANHQ_ENABLED=false ENABLE_TRADING_SERVICES=true \
  bundle exec rake trading:daemon &
NEW_DAEMON_PID=$!
echo "New Daemon PID: $NEW_DAEMON_PID"

sleep 15

grep -E "exit_already_requested|already_exited|coid|ExitEngine.*$TRACKER_ID" \
  log/trading.log | tail -20
```

Verify terminal state:

```bash
bin/rails runner "
  t = PositionTracker.find($TRACKER_ID)
  puts 'status:            ' + t.status.to_s
  puts 'exit_coid:         ' + t.exit_coid.to_s
  puts 'exit_sent_at:      ' + t.exit_sent_at.to_s
  puts 'exit_price:        ' + t.exit_price.to_s
"
```

**Pass criteria (post-restart):**
- `status: exited`.
- `exit_coid` matches `$EXPECTED_COID` exactly (no new COID).
- No duplicate exit loop symptoms in logs.
- `exit_sent_at` and `exit_price` populated.

**Repeat this entire Stage 6 sequence a second time with a fresh tracker before proceeding.**

---

## Stage 7 — Reconciliation Orphan Detection (LM3)

Simulate a DB-only orphan and ensure boot reconciliation resolves it.

```bash
# Create orphaned tracker directly — simulates mid-entry crash
bin/rails runner "
  t = PositionTracker.create!(
    order_no:    'PAPER-ORPHAN-RUNBOOK-TEST',
    security_id: '11536',
    symbol:      'NIFTY-TEST',
    segment:     'NSE_FNO',
    side:        'BUY',
    status:      'active',
    quantity:    1,
    entry_price: 100,
    avg_price:   100,
    paper:       true
  )
  puts 'Created orphan tracker id: ' + t.id.to_s
"

# Restart daemon — reconciliation should process it
kill -9 $NEW_DAEMON_PID
sleep 2

PAPER_MODE=true DHANHQ_ENABLED=false ENABLE_TRADING_SERVICES=true \
  bundle exec rake trading:daemon &
FINAL_PID=$!
sleep 10

grep -E "Bootstrap|PositionSync|reconcil|ORPHAN|orphan|PAPER-ORPHAN" \
  log/trading.log | tail -20

bin/rails runner "
  t = PositionTracker.find_by(order_no: 'PAPER-ORPHAN-RUNBOOK-TEST')
  puts 'status: ' + t.status.to_s
  puts 'exit_reason: ' + t.exit_reason.to_s
"
```

**Pass criteria:**
- Reconciliation log line appears on boot.
- Orphaned tracker is marked exited (or explicitly flagged by reconciliation policy).
- Risk manager does not treat orphan as normal active live position.

---

## Stage 8 — Stability Soak (5 Minutes)

```bash
# Watch for error storms, looped exits, duplicate actions
tail -f log/trading.log | grep -E "ERROR|FATAL|WARN|double|duplicate|loop" &
SOAK_PID=$!
sleep 300
kill $SOAK_PID 2>/dev/null

bin/rails runner "puts 'Active positions: ' + PositionTracker.where(status: 'active').count.to_s"
```

**Pass criteria:**
- No `FATAL` lines.
- No repeated exit attempts for same tracker id/coid.
- No unexpected active positions left behind.

---

## Final Go/No-Go Criteria

Mark **GO** only if all are true:
- [ ] Stage 2 passed (reconciliation before service start)
- [ ] Stage 4 passed (normal exit intent + ack persistence)
- [ ] Stage 6 passed twice (kill/restart with same COID reuse)
- [ ] Stage 7 passed (orphan resolution on boot)
- [ ] Stage 8 passed (5-minute stability soak)

If any item fails: **NO-GO for live deployment**; open incident ticket and attach logs + DB snapshots.

---

## Sign-Off Record (Required Before Live)

| Field | Value |
|---|---|
| Runbook version | `docs/runbooks/paper_mode_durability.md` |
| Date (IST) | |
| Environment | |
| Branch / commit | |
| Operator | |
| Reviewer | |
| Stage 2 | PASS / FAIL |
| Stage 4 | PASS / FAIL |
| Stage 6 Run #1 | PASS / FAIL |
| Stage 6 Run #2 | PASS / FAIL |
| Stage 7 | PASS / FAIL |
| Stage 8 | PASS / FAIL |
| Final decision | GO / NO-GO |
| Notes / Incident links | |

**Operator signature:** ____________________  
**Reviewer signature:** ____________________
