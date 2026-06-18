# Options Buying — Canonical Intraday Spec

**Authoritative reference for `algo_scalper_api` alpha work.**  
Derived from the corrected sections of `docs/options_buying_framework.md` (post–line 2054).

> **Warning:** The opening phases of `options_buying_framework.md` (vertical spreads,
> 15-minute breakout holds, 80% ATR exhaustion blocks, `MARGIN` multi-leg routing) are
> **positional reference only**. Do not implement them for intraday mode.

---

## 1. Design Thesis

Intraday long options rely on **convexity and positive gamma** — small fixed premium
risk for explosive upside on trend days. The bot is a **low win-rate / high R:R**
buyer, not a capped-spread seller.

| Rejected (positional video logic) | Required (intraday) |
| --- | --- |
| Vertical spreads (BUY + SELL legs) | **Single-leg naked long** CE or PE |
| `product_type: MARGIN`, multi-day hold | **`product_type: INTRADAY`**, square-off same day |
| Wait 15–20 min above high-OI strike | **1-minute close** + volume + OI unwind |
| Block when index moved >80% daily ATR | **Compression setup** (<30% ATR) or trade expansion days |
| ~1:1 capped spread payoff | **≥1:3 premium R:R** (config SL/TP + trailing) |

---

## 2. Scope & Indices

- **Markets:** NIFTY, BANKNIFTY, SENSEX index options (Indian F&O via DhanHQ v2 only).
- **Mode:** `options_buying.mode: intraday_scalper` (default in `config/algo.yml`).
- **Kill zones (IST):** Opening drive 09:15–10:30; closing repricing 14:00–15:15
  (see workspace SMC rules). No new entries after **15:00** (`trading_time_restrictions.block_after_time`).
- **Mandatory square-off:** 15:20 if not exited earlier.

---

## 3. Entry Pipeline (All Must Pass)

### 3.1 Structural setup — ATR compression (soft arm)

- Track index range from 09:15 using **14-day ATR** on **IDX_I** daily bars.
- **Setup window:** range < **30% of ATR₁₄** before breakout (`atr_compression.max_setup_ratio: 0.30`).
- **Inverted rule:** do **not** use the video’s “abort if >80% ATR consumed” filter.
- Compression **arms** breakout evaluation; it is not a hard veto for all intraday paths
  when `compression_arm: true`.

### 3.2 Directional bias — 15m RSI (filter, not sole trigger)

- Monitor **15-minute** index candles on **IDX_I**.
- **Bullish bias (CE):** price lower low + RSI higher low (bullish divergence).
- **Bearish bias (PE):** price higher high + RSI lower high (bearish divergence).
- Implemented via `RsiDivergenceScanner` / `RsiBiasGuard` when enabled.

### 3.3 Trigger — 1m short-covering squeeze

All three on the **option tick stream** (NSE_FNO / BSE_FNO), confirmed against **index spot** (IDX_I):

1. **1-minute candle closes** through intraday resistance (CE) or support (PE).
2. **Volume ≥ 2×** rolling baseline (`breakout.volume_multiplier: 2.0`).
3. **Open interest drops** on the strike (short covering; `require_oi_unwind: true`).

> Do **not** wait 15 minutes for “sustained” breakout — gamma flip occurs in 60–180 seconds.

### 3.4 Strike selection

- **ATM layer:** delta **0.45–0.55** (CE positive, PE negative).
- Refresh chain radar every **30 minutes**; subscribe near-the-money strikes to WebSocket.
- Liquidity floor: min volume per chain config (`chain_radar.min_volume`).

### 3.5 Pre-trade guards

| Guard | Rule |
| --- | --- |
| Bid-ask spread | Halt if spread > **1.5%** of premium (`max_bid_ask_spread_pct: 0.015`) |
| LTP freshness | Reject stale option ticks |
| Cooldown / exposure | Per-index limits, same-side caps, daily trade caps |
| Segment expectancy | Block segments with negative realized edge (min sample) |
| Circuit breaker | No entries when tripped |

---

## 4. Execution

- **Always BUY** the option contract (long gamma). Exits are **SELL**.
- **CE:** index spot breaks **above** intraday resistance / high-OI call wall.
- **PE:** index spot breaks **below** intraday support / high-OI put wall.
- **Product:** `INTRADAY` only for intraday mode — no overnight naked carry unless
  `options_buying.positional.enabled: true` (default **false**).
- **Segments:** index spot and structure on **`IDX_I`**; derivatives on **`NSE_FNO`** /
  **`BSE_FNO`**. Never use FNO segment for index LTP.
- **Idempotency:** correlation keys / guard pipeline prevent duplicate entries.

---

## 5. Risk, Exits & EV

### Premium stops (primary)

| Parameter | Default | Meaning |
| --- | --- | --- |
| `risk.sl_pct` | `0.15` | Stop at **−15%** from entry premium |
| `risk.tp_pct` | `0.45` | Target **+45%** → **R ≈ 3** |
| Break-even win rate | ~25% | `1 / (R + 1)` |

### Exit stack (priority handled by exit engine / risk manager)

- Premium R-stop, trailing (tiered / gamma-aware), profit floor, structure invalidation,
  time stop, expiry rules, mandatory square-off.
- **Index-based confirmation:** use spot index for trigger validation when option
  bid-ask is wide; do not rely on option LTP alone for structural breaks.

### Expected value before deploy

Model edge explicitly:

```
EV = (P_win × R) − (P_loss × 1)
```

Use `GET /api/analysis/:index_key/risk_explorer` (or `OptionsBuying::RiskExplorer`)
with historical ATM variance, position limits, and config SL/TP before enabling live
long-gamma deployment.

---

## 6. Time & Expiry Rules

| Rule | Value |
| --- | --- |
| No new entries after | **15:00** IST |
| Expiry-day lockout | **13:00** IST (`expiry_day.lockout_after`) |
| Square-off | **15:20** IST |
| Earliest entry (regime) | **09:30** via time-regime service |

---

## 7. Data & Architecture

```
Daily ATR (IDX_I, REST)  →  compression / setup state
Chain radar (REST)         →  strikes, resistance/support, delta filter
Index + option ticks (WS) →  1m buckets, breakout + OI unwind
Signal + guard pipeline    →  Entries::EntryGuard → Orders::Placer
Risk manager               →  ExitEngine (premium SL/TP, trailing)
```

- **Process model:** trading daemon (`ENABLE_TRADING_SERVICES=true`) — not Puma web.
- **Stable vs alpha:** iterate entry/guards/risk only; do not modify locked execution
  infra unless a Critical Scenario applies (see `CLAUDE.md`).

---

## 8. Explicit Non-Goals (Intraday Mode)

- Vertical / bull call spreads intraday
- 15–20 minute “sustained above resistance” confirmation
- 80% daily ATR exhaustion entry block
- `MARGIN` product multi-leg atomic spread routing
- Averaging down losing option positions
- Using `NSE_FNO` / `BSE_FNO` for index spot price

---

## 9. Config & Code Map

| Concern | Config / service |
| --- | --- |
| Mode switch | `options_buying.mode`, `positional.enabled: false` |
| Breakout | `options_buying.breakout.*` → `OptionsBuying::BreakoutEvaluator` |
| Chain radar | `options_buying.chain_radar.*` → `OptionsBuying::ChainRadar` |
| ATR compression | `options_buying.atr_compression.*` |
| SL/TP | `risk.sl_pct`, `risk.tp_pct` |
| EV explorer | `OptionsBuying::RiskExplorer`, `/api/analysis/:index/risk_explorer` |
| Entry orchestration | `Entries::EntryGuard`, `Entries::EntryGuardPipeline` |
| Execution | `Orders::Placer` (INTRADAY BUY/SELL) |

**Related docs:** `options_buying_implementation_plan.md` (build status),
`options_buying_framework.md` (full evolution + API reference).

---

## 10. Acceptance Checklist

- [ ] Entries are **BUY-only** single-leg **INTRADAY** options (CE or PE).
- [ ] Index structure uses **`IDX_I`**; options use **FNO** segment.
- [ ] Breakout fires on **1m** close + volume + OI unwind, not 15m hold.
- [ ] No **80% ATR exhaustion** block; compression uses **<30%** setup logic.
- [ ] Premium risk **15% / reward 45%** (or documented override) with positive EV review.
- [ ] Expiry lockout **13:00**; no new trades after **15:00**; flat by **15:20**.
- [ ] Paper mode validated before `LIVE_TRADING=true`.
