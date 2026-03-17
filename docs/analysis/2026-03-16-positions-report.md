# Position Analysis Report — 16 March 2026

**Date:** 16 March 2026  
**Mode:** Paper trading  
**Scope:** All positions created and exited on 16 Mar 2026 (IST)

---

## 1. Executive Summary

| Metric | Value |
|--------|--------|
| **Total positions** | 204 (all exited) |
| **Total realized PnL** | **−₹28,628.01** |
| **Win rate** | 47.1% (96 winners, 108 losers) |
| **Avg winner** | ₹1,271.55 |
| **Avg loser** | −₹1,395.34 |

The session was **profitable in the first hour and a half** (09:15–11:00) and **heavily loss-making in the second half**, especially 11:00–13:30 (midday) and 13:30–15:20 (afternoon). The main drivers of losses are **PREMIUM_MOMENTUM_FAILURE** exits (25 trades, −₹46,715.74) and **SENSEX** underperformance (−₹27,680.03 across 103 trades). **TRAILING_STOP** exits were strongly profitable (+₹76,294.50 on 40 trades).

---

## 2. PnL by Time Bucket (Entry Time)

| Bucket | Trades | Realized PnL (₹) | Winners | Losers |
|--------|--------|-------------------|---------|--------|
| **09:15–11:00** | 35 | **+14,066.00** | 22 | 13 |
| **11:00–13:30** | 91 | −1,826.52 | 39 | 52 |
| **13:30–15:20** | 65 | **−43,113.99** | 30 | 35 |
| **Other** | 13 | +2,246.50 | 5 | 8 |

**Findings:**

- **Morning (09:15–11:00):** Strong performance; 62.9% win rate and healthy average winner.
- **Midday (11:00–13:30):** Slight loss with more losers than winners; high trade count (91).
- **Afternoon (13:30–15:20):** Largest loss; 65 trades with many large losers (PREMIUM_MOMENTUM_FAILURE, STOP_LOSS, PREMIUM_R_STOP).

---

## 3. PnL by Index

| Index | Trades | Realized PnL (₹) | Winners | Losers |
|-------|--------|-------------------|---------|--------|
| **NIFTY** | 101 | −947.98 | 53 | 48 |
| **SENSEX** | 103 | **−27,680.03** | 43 | 60 |

**Findings:**

- **NIFTY** is close to breakeven; win rate ~52.5%.
- **SENSEX** drives almost all of the day’s loss; 58% of SENSEX trades are losers and average loss per trade is much larger than for NIFTY.

---

## 4. Exit Reason Analysis

### 4.1 By Exit Reason (All Day)

| Exit reason (abbreviated) | Count | PnL (₹) |
|---------------------------|--------|---------|
| TRAILING_STOP (Sub-second) | 40 | **+76,294.50** |
| PREMIUM_MOMENTUM_FAILURE (Sub-second) | 25 | **−46,715.74** |
| time-based exit (15:20) | 12 | +2,442.00 |
| unknown | 8 | −8,861.25 |
| STOP_LOSS (Sub-second) | 6 | −16,592.00 |
| STRUCTURE_INVALIDATION (various) | 113+ | Mixed (see below) |
| PREMIUM_R_STOP | 10 | Large negative (afternoon) |
| TIME_STOP (scalp) | 4 | Negative |
| PROFIT_FLOOR_LOCK | 3 | Positive |

### 4.2 Exit Reason by Time Bucket

**09:15–11:00 (Morning)**  
- Dominated by **STRUCTURE_INVALIDATION** (underlying level breaches). Many small PnL moves; some very large winners (e.g. +₹5,090, +₹4,610) and some losers.  
- Note: Some morning SI reasons show “underlying X broke Y” with Y as a small number (e.g. 142.75, 143.1) — these may indicate **option premium or wrong field** being used as structure level; worth verifying in code (structure_invalidation_price vs entry premium).

**11:00–13:30 (Midday)**  
- **PREMIUM_MOMENTUM_FAILURE:** 14 trades, −₹26,213.00 (main loss driver in this bucket).  
- **TRAILING_STOP:** 13 trades, +₹35,528.00.  
- **STRUCTURE_INVALIDATION:** Many trades with mixed PnL; several large SENSEX SI exits with negative PnL.

**13:30–15:20 (Afternoon)**  
- **TRAILING_STOP:** 27 trades, +₹40,766.50.  
- **PREMIUM_MOMENTUM_FAILURE:** 11 trades, −₹20,502.75.  
- **STOP_LOSS:** 6 trades, −₹16,592.00.  
- **PREMIUM_R_STOP:** 10 trades, large negative total (e.g. −₹4,236, −₹4,068, −₹4,296, etc.).  
- **unknown:** 4 trades, −₹6,910.50.

**Findings:**

- **PREMIUM_MOMENTUM_FAILURE** is the single largest loss driver (25 trades, −₹46,715.74), concentrated in **SENSEX** (20 trades, −₹44,411.99) and in **midday + afternoon** (15 + 14 trades).
- **TRAILING_STOP** is the largest profit driver and works as intended.
- **PREMIUM_R_STOP** in the afternoon locks in significant losses (premium dips slightly below stop; exit at worst point).
- **STOP_LOSS** (6%) is hitting in the afternoon on a small number of trades but with high impact (−₹16,592).

---

## 5. PREMIUM_MOMENTUM_FAILURE Deep Dive

| Segment | Count | PnL (₹) |
|---------|--------|---------|
| SENSEX | 20 | −44,411.99 |
| NIFTY | 9 | −9,218.25 |
| **11:00–13:30** | 15 | −27,838.00 |
| **13:30–15:20** | 14 | −25,792.25 |

**Interpretation:**  
The rule exits when option premium fails to make a new peak within a configured window (e.g. ~3 minutes). In choppy or mean-reverting conditions this triggers on temporary pullbacks and **crystallises losses** that might have recovered. SENSEX options (higher premium, higher volatility) are affected more.

---

## 6. Worst 15 Trades (by PnL)

| # | Symbol | Index | Entry | PnL (₹) | Exit reason |
|---|--------|--------|--------|---------|-------------|
| 1 | SENSEX-Mar2026-74700-PE | SENSEX | 13:05 | −5,520 | PREMIUM_MOMENTUM_FAILURE |
| 2 | SENSEX-Mar2026-74600-PE | SENSEX | 14:15 | −5,455 | STOP_LOSS |
| 3 | NIFTY-Mar2026-23450-CE | NIFTY | 15:17 | −5,031.50 | unknown |
| 4 | SENSEX-Mar2026-75300-PE | SENSEX | 14:31 | −4,895 | STOP_LOSS |
| 5 | SENSEX-Mar2026-75000-PE | SENSEX | 14:22 | −4,875 | PREMIUM_R_STOP |
| 6 | SENSEX-Mar2026-74800-PE | SENSEX | 14:19 | −4,815 | PREMIUM_R_STOP |
| 7 | SENSEX-Mar2026-75600-PE | SENSEX | 14:46 | −4,620 | PREMIUM_R_STOP |
| 8 | SENSEX-Mar2026-74600-PE | SENSEX | 12:00 | −4,505 | PREMIUM_MOMENTUM_FAILURE |
| 9 | SENSEX-Mar2026-74500-PE | SENSEX | 13:36 | −4,400 | PREMIUM_MOMENTUM_FAILURE |
| 10 | SENSEX-Mar2026-75600-PE | SENSEX | 14:52 | −4,296 | PREMIUM_R_STOP |
| 11 | SENSEX-Mar2026-75600-PE | SENSEX | 15:07 | −4,236 | PREMIUM_R_STOP |
| 12 | SENSEX-Mar2026-75500-PE | SENSEX | 15:03 | −4,068 | PREMIUM_R_STOP |
| 13 | SENSEX-Mar2026-74200-PE | SENSEX | 11:07 | −3,815 | STRUCTURE_INVALIDATION |
| 14 | NIFTY-Mar2026-23200-CE | NIFTY | 13:42 | −3,422.75 | PREMIUM_R_STOP |
| 15 | SENSEX-Mar2026-74500-PE | SENSEX | 12:57 | −3,385 | PREMIUM_MOMENTUM_FAILURE |

**Findings:**  
- 12 of the worst 15 are **SENSEX**; 13 of 15 are in **midday or afternoon**.  
- Exit types: **PREMIUM_MOMENTUM_FAILURE** (4), **STOP_LOSS** (2), **PREMIUM_R_STOP** (6), **STRUCTURE_INVALIDATION** (1), **unknown** (1).

---

## 7. Hold Time

| Metric | Value |
|--------|--------|
| Min | 0 s |
| Max | 480 s (8 min) |
| Median | **6 s** |
| Average | 79 s |
| **Under 2 min** | **145 (71.1%)** |

**Findings:**  
Most positions are closed within 2 minutes. This suggests either very fast stop-outs (SL / PMF / SI) or very quick trailing exits. The 6-second median points to **sub-second exit logic** (e.g. PREMIUM_MOMENTUM_FAILURE or STRUCTURE_INVALIDATION) firing very soon after entry in a large subset of trades.

---

## 8. Root Cause Summary

1. **PREMIUM_MOMENTUM_FAILURE**  
   - Exits too many trades in choppy or ranging conditions.  
   - Concentrated in SENSEX and in midday/afternoon.  
   - Consider: longer “no new peak” window, or disable in chop_decay / afternoon, or index-specific tuning.

2. **SENSEX underperformance**  
   - Higher volatility and premium; same rules (PMF, SL, PREMIUM_R_STOP, SI) trigger more often and lock losses.  
   - Consider: stricter entry filters for SENSEX, or separate exit thresholds (e.g. wider PMF window, slightly wider SL).

3. **PREMIUM_R_STOP**  
   - Afternoon exits at small LTP vs stop distance, locking large rupee losses.  
   - Consider: wider premium stop distance or time-based relaxation in late session.

4. **Structure invalidation (morning)**  
   - Some “underlying X broke Y” messages use a small Y (e.g. 142–166 range), which looks like **option premium** rather than index level.  
   - **Recommendation:** Verify that `structure_invalidation_price` and SI logic use **underlying (index) price** only, not option premium.

5. **High trade count in midday/afternoon**  
   - 91 + 65 = 156 trades in 11:00–15:20 with negative aggregate PnL.  
   - Consider: stronger session filters (e.g. fewer or no new entries in chop_decay / close_gamma) or lower max_trades_per_day in those regimes.

---

## 9. Recommendations

| Priority | Action |
|----------|--------|
| **High** | Review PREMIUM_MOMENTUM_FAILURE: relax or disable in chop_decay / afternoon, or lengthen “no new peak” window (e.g. 5 min). |
| **High** | Verify STRUCTURE_INVALIDATION uses only underlying price; fix if premium or wrong field is used as level. |
| **High** | SENSEX-specific tuning: stricter entry and/or softer PMF/PREMIUM_R_STOP for SENSEX. |
| **Medium** | PREMIUM_R_STOP: widen distance or add time/session-based override to avoid locking large losses on small LTP dips. |
| **Medium** | Reduce entries in 11:00–13:30 and 13:30–15:20 via time_regimes / trade limits or session-aware entry filters. |
| **Low** | Analyse “unknown” exit_reason (8 trades, −₹8,861) and fix logging/assignment so all exits have a reason. |

---

## 10. Data Source

- **Table:** `position_trackers`  
- **Filter:** `created_at` in 2026-03-16 (IST day range), `status = 'exited'`  
- **PnL:** `last_pnl_rupees`  
- **Exit reason:** `meta->>'exit_reason'`  
- **Index:** `meta->>'index_key'`

Report generated from production DB query. All 204 positions were paper trades.
