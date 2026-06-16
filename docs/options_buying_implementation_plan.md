# Options Buying Implementation Plan

Maps the **intraday scalper** framework to `algo_scalper_api`. **Canonical strategy rules:**
`docs/options_buying_intraday_spec.md`. Ep-92 positional logic is reference-only unless
`mode: positional` and carry is allowed.

---

## 1. Alignment Table

| Pillar | Intraday | Positional (carry-gated) | Component |
| :--- | :--- | :--- | :--- |
| Multi-confirmation pipeline | **Implemented** | N/A | `Entries::EntryGuardPipeline` |
| 9:30 earliest entry | **Implemented** | Same | `Live::TimeRegimeService` |
| Option chain / OI | **Implemented** | Same | `Options::ChainAnalyzer`, `OptionsBuying::ChainRadar` |
| 1m breakout + OI unwind | **Implemented** | N/A | `OptionsBuying::BreakoutWatcher`, `BreakoutReadyGuard` |
| ATR compression setup | Soft arm (intraday) | Hard gate (carry) | `AtrCompressionChecker`, `CompressionSetupGuard` |
| ATR exhaustion block | **Removed** | **Removed** | Was `ATRExhaustionGuard` — reverted |
| Naked INTRADAY execution | **Implemented** | N/A | `Orders::Placer` (`product_type: INTRADAY`) |
| Vertical spreads | N/A | **Deferred** | Documented in framework doc |
| 15–20 min OI hold | N/A | **Deferred** | Positional reference only |
| RSI divergence bias | **Implemented** | Optional | `RsiDivergenceScanner`, `RsiBiasGuard` |
| 1:3 premium R:R | **Configured** | N/A | `risk.sl_pct: 0.15`, `risk.tp_pct: 0.45` |
| Bid-ask spread guard | **Implemented** | Same | `BidAskSpreadGuard` |
| No averaging down | **Enforced** | Same | Exit engine + guards |

---

## 2. Intraday Data Flow

```
Solid Queue (09:08)  → DailyMetricsJob     → Redis daily ATR
Solid Queue (09:16+) → ChainRadarJob       → resistance, radar strikes, RSI bias
MarketFeedHub ticks  → BreakoutWatcher     → 1m buckets → BreakoutEvaluator
Signal::Engine       → EntryGuard          → guard pipeline → Orders::Placer
RiskManager          → ExitEngine          → premium SL/TP + trailing
```

---

## 3. Config (`config/algo.yml`)

```yaml
options_buying:
  mode: intraday_scalper
  atr_compression:
    enabled: true
    max_setup_ratio: 0.30
  breakout:
    enabled: true
    timeframe_minutes: 1
    volume_multiplier: 2.0
    require_oi_unwind: true
    compression_arm: true
  chain_radar:
    enabled: true
    delta_min: 0.45
    delta_max: 0.55
  execution:
    spread_enabled: false
    max_bid_ask_spread_pct: 0.015
  positional:
    enabled: false
    require_carry_allowed: true
  expiry_day:
    lockout_after: "13:00"

risk:
  sl_pct: 0.15
  tp_pct: 0.45
```

---

## 4. Guard Pipeline Order (new guards)

After `InstrumentLookupGuard`:

1. `CompressionSetupGuard` — positional + carry only
2. `LtpResolutionGuard`
3. `BidAskSpreadGuard`
4. `BreakoutReadyGuard` — intraday; skips until chain radar seeds resistance
5. `RsiBiasGuard`

---

## 5. Positional Gap (v2)

| Item | Status |
| :--- | :--- |
| Spread orchestrator | Not implemented — requires locked `Orders::Placer` change |
| 15–20 min OI hold timer | Not implemented — use breakout path intraday |
| `product_type: MARGIN` multi-leg | Deferred |

Enable with `options_buying.mode: positional` and `positional.enabled: true` when DTE ≥ 1.

---

## 6. Verification

```bash
bundle exec rspec spec/services/options_buying/ spec/jobs/options_buying/ \
  spec/services/entries/guards/compression_setup_guard_spec.rb \
  spec/services/entries/guards/breakout_ready_guard_spec.rb \
  spec/services/entries/guards/bid_ask_spread_guard_spec.rb
bundle exec rspec spec/services/entries/entry_guard_integration_spec.rb
bundle exec rubocop app/services/options_buying/ app/jobs/options_buying/
rails db:migrate
rails solid_queue:load_recurring
```

## 7. Stream Hybrid

See [options_buying_stream_architecture.md](options_buying_stream_architecture.md) and [options_buying_ingestion_sidecar_future.md](options_buying_ingestion_sidecar_future.md).

Trading daemon restart required after bootstrap changes.
