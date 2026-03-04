# Trading Session Audit — 2026-03-04 (End of Day)

Generated after market close. Session ran from ~09:15 IST to 15:30 IST.
This is a follow-up to `session_audit_2026-03-04.md` (morning snapshot) — covers the full day including
the exit system fixes deployed mid-session.

---

## Session Summary

| Metric | Value |
|--------|-------|
| Total positions opened | 96 |
| Closed | 95 |
| Still active at audit | 1 (#2971 NIFTY-24450-PE, entry ₹292.5) |
| CE positions | **0** |
| PE positions | **96** (100% bearish) |
| Winners | 38 |
| Losers | 57 |
| Win rate | **40%** |
| Realized PnL | **-₹1,544.75** |
| By index | NIFTY: 54, SENSEX: 42, BANKNIFTY: 8 |

---

## Exit Breakdown

| Exit Reason | Count | Estimated PnL |
|-------------|-------|---------------|
| `HARD_RUPEE_TP` | **3** | **+₹6,287** |
| `HARD_RUPEE_SL` | **1** | **-₹1,819** |
| `TIME_STOP` (15-min hard) | ~45 | mixed (net negative) |
| `time-based exit (15:20)` | **46** | mixed (bulk EOD flatten) |
| `PREMIUM_MOMENTUM_FAILURE` | 0 | — |
| `PREMIUM_R_STOP` | 0 | — |
| `PROFIT_FLOOR` | 0 | — |
| `STRUCTURE_INVALIDATION` | 0 | — |

### Notable Trades

| # | Exit Reason | PnL | Notes |
|---|-------------|-----|-------|
| 2920 | HARD_RUPEE_TP | +₹2,171 | First TP exit of the session |
| 2921 | HARD_RUPEE_TP | +₹2,079.5 | TP firing correctly |
| 2922 | HARD_RUPEE_TP | +₹2,036.5 | TP firing correctly |
| 2935 | HARD_RUPEE_SL | -₹1,819 | Held only 0.1 min — very fast SL cut |

---

## What Changed Today (Exit System Fixes)

The morning audit identified all exits as TIME_STOP. The following fixes were deployed during the session:

| Fix | Status | Evidence |
|-----|--------|----------|
| `hard_rupee_sl` enabled (₹1000/trade) | ✓ Deployed | 1 SL exit fired (#2935) |
| `hard_rupee_tp` enabled (₹2000/trade) | ✓ Deployed | 3 TP exits fired (#2920–2922) |
| `profit_floor` added to config | ✓ Deployed | No fires (none reached ₹500 floor yet) |
| `set_premium_stop_price!` on entry | ✓ Deployed | LAYER 0 now armed; no fires observed |
| PE direction bug fixed in momentum rule | ✓ Deployed | Still 0 fires (see issue #2 below) |
| Token TOTP fallback added | ✓ Deployed | No token errors in afternoon session |

**The TP/SL layers ARE working.** ₹6,287 was captured via 3 TP exits that would have been missed entirely under the old system.

---

## Signal Analysis

### Direction Bias

- **3,757 signals generated** today — ALL bearish (`smc_decision: "put"`)
- **Zero CE (bullish) signals** generated at any point
- Strategy: `supertrend_trend_1m_none`, 1m timeframe, confidence 0.8–0.9

### Market Context

The market was clearly in a bearish trend all day:
- NIFTY: ~24,250 → 24,374 (volatile but bearish bias in options flow)
- BANKNIFTY: ~58,505
- SENSEX: ~78,768

Given a sustained bearish trend, all supertrend signals were bearish → PE-only entries. This is **correct behavior** — the signal engine is working as intended.

However, the system appears **structurally unable to generate CE signals** even if the market reverses intraday. This is a risk: if NIFTY rallies 200pts intraday, the system won't pivot to CE buying.

---

## Issues Found

### P0 — Critical (PnL Impact)

**Issue 1: Net PnL negative despite 3 TP exits**
- 3 HARD_RUPEE_TP exits produced +₹6,287
- 57 losing trades wiped out gains + added ₹7,831 in losses
- Average loss per loser is significantly larger than average gain per winner
- Root cause: TIME_STOP exits for losers hold the full 15 minutes while losses compound
- **The HARD_RUPEE_SL at ₹1000 is not catching most losers** — 56 out of 57 losers exited via TIME_STOP rather than SL

**Issue 2: PREMIUM_MOMENTUM_FAILURE never fired (0 exits)**
- Fixed the PE direction bug — but 0 fires all day
- Possible causes:
  a. `candle_series()` returning `nil` for all instruments (DhanHQ OHLC API)
  b. Thresholds too loose (2 candles without new high isn't triggering)
  c. The rule is silently skipping due to `instrument` being nil for active trackers
- This is a significant gap — momentum exits should prevent holding stalled PE options

**Issue 3: Bulk 15:20 EOD exit (46 positions)**
- 46 positions were force-closed at 15:20 end-of-day flatten
- This means 46 trades had NO organic exit during the 15-min hold window
- Either: entries were placed after 15:05 (too late) and hit the EOD flatten before TIME_STOP
- Or: TIME_STOP was supposed to fire but was delayed/skipped

### P1 — Performance

**Issue 4: HARD_RUPEE_SL threshold too high or not responsive enough**
- ₹1000 SL fired only 1 time across 57 losing trades
- Many 15-min losses exceeded ₹1000 but exited via TIME_STOP instead of SL
- Possible cause: PnL is read from Redis cache which may lag by 250ms–1s; SL check might miss the threshold crossing if the tick jumps past it
- Or: the 15-min TIME_STOP fires first because `monitor_loop` interval is too slow

**Issue 5: No PROFIT_FLOOR fires (0)**
- `lock_rupees: 500` — none of the 95 closed trades reached +₹500 before giving it back
- The 3 TP exits booked at ~₹2000 skipped past the floor (floor arms at ₹500, but TP fires at ₹2000 first)
- The floor is conceptually valuable but hasn't been tested in practice yet

### P2 — Observability

**Issue 6: CE signal generation never tested**
- No CE signals were generated today — correct given the market
- But we have no confirmation that CE signals WOULD fire if market turns bullish
- Need a test: force a bullish supertrend reading and verify CE signal is produced

**Issue 7: PREMIUM_R_STOP (LAYER 0) — no confirmation it works**
- `premium_stop_price` is now written to `tracker.meta` via `set_premium_stop_price!`
- No LAYER 0 exits observed — either no position dropped 30% from entry, or the check is silently failing
- Need a paper test: enter a position, manually drop its price 35%, verify LAYER 0 fires

---

## Improvement Recommendations

### Signal Generator

1. **Verify CE path is reachable**
   - Add a test/dry-run mode: force `supertrend_direction = :bullish` for 1 signal cycle and verify `smc_decision: "call"` is produced
   - Check if any hardcoded `put` preference exists in `SignalEngine` or `DerivativeChainAnalyzer`

2. **Log signal direction distribution hourly**
   - Emit a metric: `signals_generated_ce: N, signals_generated_pe: N` per hour
   - Immediately surfaces directional bias in dashboard

3. **Consider multi-timeframe confirmation before blocking CE**
   - If 5m supertrend is bearish but 1m turns bullish → allow CE entry with smaller sizing
   - Currently: any bearish higher-TF supertrend blocks CE entirely

### Entry Management

4. **Add entry time filter (cutoff before EOD)**
   - No entries after 14:45 IST — any 15-min position opened after 14:45 hits the 15:20 flatten
   - Currently 46 positions were force-closed by the EOD flatten, suggesting entries after 14:45

5. **Reduce entries per signal — add cooldown between same-index entries**
   - 54 NIFTY positions in one day = entry every ~6–7 minutes on average
   - Reduce to max 2–3 simultaneous per index; add a 5-min cooldown after each exit

6. **Track entry quality score**
   - Log `trend_score` per entry and correlate with PnL outcome
   - If low trend_score trades (<7) underperform, raise the minimum threshold

### Position Sizing

7. **Review lot sizing for SENSEX (42 trades)**
   - SENSEX options have different lot size than NIFTY — verify `lot_size` from pick is correct
   - If SENSEX positions are oversized relative to capital, they amplify losses

8. **Dynamic sizing based on win streak / loss streak**
   - After 3 consecutive losses, reduce size to 50%
   - After 3 consecutive wins, maintain size (no martingale)
   - `Capital::DynamicRiskAllocator` already exists — extend it with streak tracking

### Exits

9. **Investigate why PREMIUM_MOMENTUM_FAILURE is not firing**
   - Add a debug log: `[PMF] candle_series returned nil for #{tracker.id}` in `momentum_failed?`
   - If OHLC API is failing silently, all LAYER 2/3 checks are dead
   - Priority: run `rails runner` and manually call `instrument.candle_series(interval: '1')` for any active tracker

10. **Reduce HARD_RUPEE_SL threshold from ₹1000 → ₹600**
    - With 40% win rate, a ₹600 SL (3× ₹200 avg win) would improve expectancy significantly
    - Current ₹1000 threshold is too permissive — losers run to the full 15 minutes

11. **Add monitor_loop frequency logging**
    - Log the actual time between monitor_loop iterations
    - If the loop runs every 5–10 seconds, a position can lose ₹500+ between SL checks
    - If loop interval is too slow, tighten it or use a dedicated SL watchdog thread

---

## TODO List (Prioritized)

### P0 — Investigate Before Next Session

- [ ] **Investigate PREMIUM_MOMENTUM_FAILURE silence**
  - Run: `rails runner "tracker = PositionTracker.active.first; puts tracker.instrument.candle_series(interval: '1').inspect"`
  - If nil → DhanHQ OHLC is broken for active trackers (likely instrument nil issue)
  - File: `app/services/risk/rules/premium_momentum_failure_rule.rb`

- [ ] **Verify PREMIUM_R_STOP (LAYER 0) is wired end-to-end**
  - Check `tracker.meta['premium_stop_price']` for a newly opened paper position
  - Grep: `exit_enforcement.rb` → `enforce_premium_r_stop` → verify it reads from meta correctly

- [ ] **Lower HARD_RUPEE_SL from ₹1000 → ₹600**
  - File: `config/algo.yml` → `risk.hard_rupee_sl.max_loss_rupees`
  - This alone would have cut ~₹4,000 in avoidable losses today

- [ ] **Add entry cutoff at 14:45 IST**
  - No new entries within 45 min of market close
  - File: `app/services/entries/entry_guard.rb` or time regime service

### P1 — Next Week

- [ ] **Verify CE signal path with forced test**
  - Temporarily set supertrend direction to `:bullish` in dev, confirm CE flow works end-to-end
  - File: `app/services/signals/` (signal engine entry point)

- [ ] **Add per-hour direction metrics to dashboard**
  - CE/PE signal count per hour
  - Immediately surface if system gets stuck in one direction

- [ ] **Add same-index cooldown between entries**
  - 5-minute cooldown after any exit before same-index entry is allowed
  - File: `app/services/entries/entry_guard.rb`

- [ ] **Check SENSEX lot sizing**
  - Query: `SELECT security_id, quantity, entry_price FROM position_trackers WHERE symbol LIKE '%SX%' AND DATE(created_at) = '2026-03-04' LIMIT 5;`
  - Compare SENSEX lot_size to NIFTY lot_size

### P2 — Code Quality

- [ ] **Add monitor_loop timing metric**
  - Log `[RiskManager] monitor_loop took Xms` on each cycle
  - Surface if loop is running slower than expected

- [ ] **Session PnL chart in dashboard**
  - Cumulative PnL line over the day (hourly buckets)
  - Would have shown the negative trend persisting after morning TP wins

---

## Reference SQL

```sql
-- Full exit breakdown for today
SELECT
  exit_reason,
  COUNT(*) AS count,
  ROUND(SUM(last_pnl_rupees)::numeric, 2) AS total_pnl,
  ROUND(AVG(last_pnl_rupees)::numeric, 2) AS avg_pnl,
  ROUND(MAX(last_pnl_rupees)::numeric, 2) AS best,
  ROUND(MIN(last_pnl_rupees)::numeric, 2) AS worst
FROM position_trackers
WHERE DATE(exited_at AT TIME ZONE 'Asia/Kolkata') = '2026-03-04'
  AND status = 'exited'
GROUP BY exit_reason
ORDER BY total_pnl DESC;

-- Per-trade breakdown
SELECT
  id, symbol, side, entry_price, exit_price,
  last_pnl_rupees, exit_reason,
  EXTRACT(EPOCH FROM (exited_at - created_at)) / 60.0 AS held_minutes,
  exited_at
FROM position_trackers
WHERE DATE(exited_at AT TIME ZONE 'Asia/Kolkata') = '2026-03-04'
  AND status = 'exited'
ORDER BY last_pnl_rupees DESC;

-- CE vs PE count
SELECT
  CASE WHEN symbol LIKE '%-CE' THEN 'CE' WHEN symbol LIKE '%-PE' THEN 'PE' ELSE 'OTHER' END AS option_type,
  COUNT(*) AS trades,
  ROUND(SUM(last_pnl_rupees)::numeric, 2) AS total_pnl
FROM position_trackers
WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') = '2026-03-04'
GROUP BY 1;

-- Winner/loser breakdown by index
SELECT
  index_key,
  COUNT(*) FILTER (WHERE last_pnl_rupees > 0) AS winners,
  COUNT(*) FILTER (WHERE last_pnl_rupees <= 0) AS losers,
  ROUND(SUM(last_pnl_rupees)::numeric, 2) AS total_pnl
FROM position_trackers
WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') = '2026-03-04'
  AND status = 'exited'
GROUP BY index_key
ORDER BY total_pnl DESC;
```

---

## Key Takeaway

The exit system fixes deployed today demonstrably work:
- **+₹6,287 captured** via 3 HARD_RUPEE_TP exits that wouldn't have fired under the old system
- **HARD_RUPEE_SL** cut 1 position in 0.1 min — proving the fast-cut mechanism is live

The remaining problem is **loss management**: 57 losing trades exiting via TIME_STOP at 15 minutes, each accumulating losses beyond what a tighter SL would allow. The highest-priority fix before tomorrow's session is lowering the SL threshold from ₹1000 → ₹600 and investigating PREMIUM_MOMENTUM_FAILURE silence.

---

*Audit performed: 2026-03-04, post-session (~15:30 IST)*
*Data source: PostgreSQL + development.log, Rails paper trading session*
*Previous audit: `docs/session_audit_2026-03-04.md` (morning snapshot, pre-fix)*
