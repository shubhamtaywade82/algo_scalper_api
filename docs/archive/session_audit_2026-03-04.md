# Trading Session Audit — 2026-03-04

Generated from live session review. Rails server running since Indian market open (~09:15 IST).

---

## Session Summary

| Metric | Value |
|--------|-------|
| Trades closed | 24 |
| Still active | 2 (IDs: 2900, 2901) |
| Winners | 12 |
| Losers | 12 |
| Win rate | 50% |
| Realized PnL | ₹1,689.00 |
| Unrealized PnL | −₹50.75 |
| **Net PnL** | **₹1,638.25** |
| HWM total (all trades) | ₹27,587.50 |
| **Left on table** | **₹25,898.50** |

Exit efficiency: **~6.1%** — only 6 cents of every rupee of peak profit was captured.

---

## CRITICAL ISSUE: All Exits Are TIME_STOP

**Every single one of the 24 closed trades exited via TIME_STOP (15-minute hard stop).**

- Stop-loss exits: 0
- Take-profit exits: 0
- Trailing stop exits: 0
- Supertrend reversal exits: 0

This means:
- Winning trades are NOT locking in profit early — they run the full 15 minutes and often give back gains
- Losing trades are NOT being cut short — they ride down for the full 15 minutes compounding losses
- The risk/reward is essentially: hold blindly for 15 minutes, then exit at whatever price

### Worst Example

**Trade #8** (NF-24250-PE):
- Entry: ₹259.40, HWM PnL: +₹259.50 (peaked ~+100% intraday)
- Actual exit PnL: −₹2,438.00
- Swung from near-double to -₹2,438 with **no stop-loss triggered**

### Best-Performing Trades (exits that actually worked)

Trades 23 & 24 only left ₹21 and ₹26 on table respectively — suggesting the timing occasionally aligned but purely by luck, not mechanism.

---

## System Observations

### Singleton Isolation in Rails Runner

When running `rails runner` for audit queries, these showed as inactive:
- `Live::PnlUpdaterService.instance.running?` → `false`
- `Live::MarketFeedHub.instance.running?` → `""` (empty string)

This is expected — Rails runner spawns a separate process, so the singletons are fresh/unstarted. The live server process has its own singleton instances. **Not a bug, but worth noting** for any future runner-based health checks.

### Duplicate DB Writes

Observed 3 UPDATE statements per position per tick in the Rails log:
```
UPDATE "position_trackers" SET "high_water_mark_pnl" = ... WHERE "id" = 2900
UPDATE "position_trackers" SET "last_pnl_rupees" = ... WHERE "id" = 2900
UPDATE "position_trackers" SET "updated_at" = ... WHERE "id" = 2900
```

These should ideally be batched into a single `update_columns` call. At high tick frequency this creates unnecessary DB load.

### EntryGuard Log Noise

Log is flooded with:
```
[EntryGuard] Supertrend exposure check failed: Active position already exists for NSE_FNO
```

This is expected behavior (guard working correctly) but is logged at INFO/WARN level. Should be DEBUG to reduce noise.

### Tick Cache State (at time of audit ~12:30)

- 12 entries in tick cache
- NIFTY: 24,374.60
- BANKNIFTY: 58,505.45
- SENSEX: 78,768.06
- Circuit breaker: safe ✓

---

## TODO / Investigation Priorities

### P0 — Critical (affects PnL directly)

- [x] **Root causes of TIME_STOP-only exits — INVESTIGATED & FIXED (2026-03-04)**
  - LAYER 0 (premium_r_stop): `premium_stop_price` was never set in tracker.meta → fixed in `entry_manager.rb`
  - LAYER 1 (hard_rupee_sl): disabled in config → **enabled** (`hard_rupee_sl.enabled: true`)
  - PROFIT_FLOOR: not configured → **added** `profit_floor:` section to `algo.yml`
  - LAYER 3 (premium_momentum_failure): **direction bug fixed** — PE branch was checking new lows instead of new highs
  - NEW TP LAYER: **added** `enforce_hard_rupee_take_profit` method + wired into runner loop; enabled config
  - LAYER 2 (structure_invalidation): still depends on candle_series() API — follow-up investigation needed

- [ ] **Check ExitEngine is wired to trailing/risk callbacks**
  - Grep for `ExitEngine` call sites — confirm it's not only called at TIME_STOP

### P1 — Performance / Correctness

- [ ] **Reduce duplicate DB writes per tick**
  - Consolidate multiple `update!` / `update_columns` calls on PositionTracker into one
  - Consider batching via PnlUpdaterService (already has 250ms flush interval)

- [ ] **Fix EntryGuard log level**
  - Change "Active position already exists" log from WARN → DEBUG
  - File: `app/services/entries/entry_guard.rb`

- [ ] **Investigate HWM tracking accuracy**
  - Total HWM ₹27,587.50 vs ₹1,689 realized — verify HWM is being computed from tick data correctly
  - Is `high_water_mark_pnl` being reset on each new position or accumulating?

### P2 — Monitoring / Observability

- [ ] **Dashboard: PnlUpdaterService health indicator**
  - Currently uses `Live::MarketFeedHub.instance.running?` which returns empty string, not bool
  - Fix `build_dashboard_stats` system health to use explicit boolean check

- [ ] **Add exit reason breakdown to dashboard**
  - Pie/count of TIME_STOP vs SL vs TP vs TRAIL — immediately surfaces the issue above

- [ ] **Session performance chart**
  - Cumulative PnL line over the day
  - Would have immediately shown the flat/downward trend after early morning HWMs

### P3 — Code Quality

- [ ] **Runner-based health check script**
  - Cannot use singleton `.running?` in runner context
  - Use DB/Redis state checks instead (active threads by name, Redis key presence)

---

## Per-Trade Breakdown (today's closed positions)

| # | Symbol | Side | Entry | Exit | PnL | HWM | Left on table | Exit reason |
|---|--------|------|-------|------|-----|-----|---------------|-------------|
| 1–22 | various | — | — | — | mixed | large | ~₹25,000+ | TIME_STOP |
| 23 | SX-78800-PE | — | — | — | small+ | ~same | ₹21 | TIME_STOP |
| 24 | NF-24350-PE | — | — | — | small+ | ~same | ₹26 | TIME_STOP |

*Full per-trade table requires re-querying DB — see audit query below.*

```sql
-- Re-run to get full breakdown
SELECT
  id, symbol, side, entry_price, exit_price,
  last_pnl_rupees, high_water_mark_pnl,
  (high_water_mark_pnl - last_pnl_rupees) AS left_on_table,
  exit_reason,
  EXTRACT(EPOCH FROM (exited_at - created_at)) / 60.0 AS held_minutes,
  exited_at
FROM position_trackers
WHERE DATE(exited_at AT TIME ZONE 'Asia/Kolkata') = '2026-03-04'
  AND status = 'exited'
ORDER BY exited_at;
```

---

## Files to Investigate

```
app/services/live/risk_manager_service.rb      # Does it call ExitEngine for SL?
app/services/live/trailing_engine.rb           # Is it receiving ticks? Calling ExitEngine?
app/services/live/exit_engine.rb               # How is TIME_STOP set vs SL/TP?
app/models/position_tracker.rb                 # subscribe method — is it wiring ticks to engines?
config/algo.yml                                # risk section — SL/TP thresholds
```

---

*Audit performed: 2026-03-04, mid-session (~12:30 IST)*
*Session start: ~09:15 IST (market open)*
*Data source: PostgreSQL + Redis, live Rails server process*
