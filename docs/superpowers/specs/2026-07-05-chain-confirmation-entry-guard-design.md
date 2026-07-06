# Chain Confirmation Entry Guard — Live OI/IV/Delta Confirmation for Momentum Entries

**Date:** 2026-07-05
**Approach:** New `Options::ChainWatchRegistry` + `Entries::Guards::ChainConfirmationGuard`, reusing the already-running `Options::ChainWatchService` instances
**Branch:** `feature/options-buying-improvements`

## Context

The autonomous trading pipeline already picks direction (bullish→CE, bearish→PE) via `Signal::Engine`'s Supertrend+ADX+regime detection, selects a strike via `Options::ChainAnalyzer`, and runs the pick through a 32-guard `Entries::EntryGuardPipeline` before placing an order. Two existing guards check options-market data at entry time: `IvVolGateGuard` (IV rank vs 30-day history) and `OptionVolumeVelocityGuard` (tick-volume rate vs baseline) — both in `app/services/entries/guards/`, both self-contained `self.call(context)` classes with `AlgoConfig.fetch.dig(:risk, ...)` config and fail-open error handling.

Neither existing guard reads live OI, OI-change, or delta on the picked strike. `Options::ChainAnalyzer`'s own OI/IV/delta filtering happens earlier, during strike *selection* — not as a post-selection entry *confirmation* gate.

Separately, this session built `Options::ChainWatchService` (one instance per index — NIFTY/BANKNIFTY/SENSEX — registered in `lib/trading_system/bootstrap.rb`'s supervisor, running always-on inside the trading daemon) which continuously maintains a live snapshot per index: spot, ATM strike, and ATM±5 legs each with `ltp/oi/oi_change/iv/delta/gamma/theta/vega`. This is exactly the confirmation data a new guard needs — it should not be recomputed, only read.

**Key constraint:** `ChainWatchService` instances are long-running, created once at daemon boot. A guard cannot do `Options::ChainWatchService.new(index_key:).snapshot` — that would construct a fresh, unstarted instance with empty data. The guard and the running services live in the same daemon process (no cross-process boundary here, unlike this session's earlier ActionCable work), so a small in-process registry is enough to let the guard reach the already-running instance's live state.

## Scope

- New guard: `Entries::Guards::ChainConfirmationGuard`, checking OI direction, IV band, and delta band on the already-picked strike, positioned in `EntryGuardPipeline`'s handler array immediately after `OptionVolumeVelocityGuard`.
- New registry: `Options::ChainWatchRegistry`, populated by `bootstrap.rb` at the same point `ChainWatchService` instances are created, read by the new guard.
- Fail-open on any missing/stale data or error — consistent with `IvVolGateGuard`/`OptionVolumeVelocityGuard`'s existing convention. Missing confirmation data never blocks a trade the other guards already approved.
- New config block `risk.chain_confirmation_gate` in `config/algo.yml`, following the `iv_vol_gate`/`volume_velocity_gate` pattern.
- Out of scope: any change to `Options::ChainWatchService` itself, `Options::ChainAnalyzer` (LOCKED, strike selection), `EntryFilterEngine` (separate candle/series-based mechanism, not touched), or the guard pipeline's existing 32 guards beyond adding one new entry.

## Design

### Architecture

```
ChainWatchService (per index, already running in daemon) ──registers self──> Options::ChainWatchRegistry
                                                                                       │
Signal::Engine → EntryGuard.try_enter → EntryGuardPipeline                            │
  ... IvVolGateGuard, OptionVolumeVelocityGuard,                                       │
  Guards::ChainConfirmationGuard.call(context) ──reads snapshot_for(index_key)────────┘
  ... remaining guards ...
```

### `Options::ChainWatchRegistry`

New class, `Concurrent::Hash` keyed by upcased index_key → the running `ChainWatchService` instance. Two methods: `.register(index_key, service)` and `.snapshot_for(index_key)` (returns that service's `#snapshot`, or `nil` if the index was never registered — e.g. skipped by Task 4's boot-resilience rescue). `bootstrap.rb` calls `.register` immediately after each successful `ChainWatchService.new` + `supervisor.register` — inside the same `begin/rescue` block used for the boot-resilience fix, so an index that fails to register a service also never appears in the registry.

### `Entries::Guards::ChainConfirmationGuard`

Follows `IvVolGateGuard`'s exact shape: `include BaseGuard`, single `self.call(context)`, config via `AlgoConfig.fetch.dig(:risk, :chain_confirmation_gate)`, `rescue StandardError` → `PASS`.

1. Return `PASS` immediately if `enabled?` is false (config gate, matching sibling guards).
2. `snapshot = Options::ChainWatchRegistry.snapshot_for(context[:index_cfg][:key])` — return `PASS` if `nil` or `snapshot[:chain_stale]` is true.
3. Determine expected option type from `context[:direction]` (bullish→CE, bearish→PE — same mapping `Signal::Engine` already uses elsewhere).
4. Find the leg in `snapshot[:legs]` matching `context[:pick][:strike]` and the expected type. Return `PASS` if no matching leg (strike outside the ATM±5 window ChainWatchService tracks — expected for far-OTM/ITM picks, not a signal failure).
5. Check three conditions against config thresholds:
   - OI direction: `leg[:oi_change]` must be ≥ `min_oi_change` (rising OI in the traded direction; a negative/flat OI-change on the picked leg suggests the move isn't backed by fresh positioning).
   - IV band: `leg[:iv]` between `min_iv` and `max_iv` (avoids entering into an IV blow-off extreme).
   - Delta band: `leg[:delta].abs` between `min_delta` and `max_delta` (avoids deep ITM/far OTM picks that slipped through strike selection).
6. Any condition failing → `{blocked: "<descriptive reason with actual vs threshold values>"}`, matching sibling guards' message style. All passing → `PASS`.
7. Any exception anywhere in the above (nil leg fields, registry lookup failure, etc.) → `rescue StandardError` → `PASS`, logged at `debug` level (fail-open is expected/normal here, not a fault worth `warn`/`error`).

### `EntryGuardPipeline` change

One new line in the handler array (`app/services/entries/entry_guard_pipeline.rb`), inserted immediately after the existing `OptionVolumeVelocityGuard` entry.

### Config (`config/algo.yml`)

```yaml
risk:
  chain_confirmation_gate:
    enabled: true
    min_oi_change: 0
    min_iv: 8.0
    max_iv: 45.0
    min_delta: 0.25
    max_delta: 0.75
```

### Error Handling

- Registry has no entry for the index (service failed to start, or daemon just booted and hasn't registered yet) → `PASS`.
- Snapshot exists but `chain_stale: true` (REST poll failing) → `PASS`.
- No leg matches the picked strike/type in the ATM±5 window → `PASS`.
- Any other exception → `rescue StandardError` → `PASS`, per this guard's fail-open design and this codebase's established guard convention.

### Testing

- `spec/services/options/chain_watch_registry_spec.rb` — register/lookup, missing-index returns nil.
- `spec/services/entries/guards/chain_confirmation_guard_spec.rb` — following `iv_vol_gate_guard_spec.rb`'s existing pattern: table-test pass/block cases for each of OI/IV/delta independently, plus fail-open cases (disabled config, nil snapshot, stale snapshot, no matching leg, registry exception).
- No live-market integration test — guard logic is fully unit-testable against a mocked registry snapshot, consistent with this codebase's existing guard test conventions.
