# SMC Structure Event Log — Design

**Date:** 2026-07-07
**Status:** Approved (sub-project 1 of 4 in the Analysis Layer initiative — see context below)

## Context

This is the first of four sub-projects decomposed from a larger "Analysis Layer" spec
(feature store, context/regime/structure/OI/IV engines, strike ranking, trade scoring,
counterfactual tracking). A repo audit found most of that spec already implemented under
existing names (`OptionsBuying::TradeScoringEngine`, `MarketContext::RegimeComposer`,
`Options::FlowAnalyzer`, `Options::IvRankTracker`, etc.). The genuinely missing piece
addressed here: an append-only log of atomic market-structure events with parent
references, as opposed to the current coarse "signal" event snapshot.

Planned order for the remaining sub-projects (separate specs): (2) snapshot/manifest
layer, (3) IV/OI engine consolidation, (4) counterfactual tracker.

## Current State (verified by direct code inspection, not assumption)

- `app/services/smc/structure_engine.rb` — simplified swing/BOS calculator, used only by
  `Smc::TradingSignalContract.build`.
- `app/services/smc/trading_signal_contract.rb` — builds one composite payload per call
  (structure + zones + liquidity + displacement + volume + mtf), publishes it as a single
  `event_type: 'signal'` row via `EventStore::Publisher` to the `smc_events` table, using a
  **new random `correlation_id` (UUID) per call** unless one is passed in.
- `app/services/smc/scanner.rb` — calls `EventStore::Publisher.publish!` directly too
  (line 280); runs on a 5-minute cadence per `lib/trading_system/bootstrap.rb`
  (`Smc::Scanner`, service #11).
- `app/models/smc_event.rb` / `EventStore::Publisher` / `EventStore::ReplayEngine` — a
  working, generic, append-only event log already exists: `stream`, `event_type`,
  `correlation_id`, `payload` (jsonb), auto-incrementing `sequence` scoped to
  `correlation_id`. Replay orders by `created_at, sequence`. **This is reused as-is** — no
  new table, no new publisher.
- `app/services/smc/detectors/*` — richer, already-built atomic detectors
  (`SwingStructure`, `Structure` [BOS/CHoCH], `Fvg`, `OrderBlocks`, `Liquidity` [sweeps],
  `InternalStructure`, `PremiumDiscount`) that are **currently unused** except by dead code.
- `app/services/smc/analyzer.rb` (`Smc::Analyzer`) — a phase state machine
  (Trap → Expansion → Trend → Entry Zone) that is **never instantiated anywhere in the
  codebase** (confirmed via `grep -rn "Smc::Analyzer\.new"` — zero hits outside its own
  file). Dead code.
- `app/services/smc/structure_store.rb` (`Smc::StructureStore`) — mutable single-key Redis
  blob, last-write-wins, no history. Only ever instantiated by the dead `Smc::Analyzer`.
  Also dead code (transitively).

## Goal

Emit each atomic structural event (swing high/low, BOS, CHoCH, FVG created, order block
formed, liquidity sweep) as its own append-only `smc_events` row, with a `parent_event_id`
in the payload linking related events (e.g. a CHoCH references the BOS it reversed; a sweep
references the swing level it took out). This gives a real, replayable structural history
per instrument instead of one coarse blob per signal call.

## Design

### New: `Smc::StructureEventRecorder`

```ruby
Smc::StructureEventRecorder.record!(symbol:, interval:, series:)
```

Responsibilities:

1. Run the existing detectors against `series`: `Detectors::SwingStructure`,
   `Detectors::Structure` (BOS/CHoCH), `Detectors::Fvg`, `Detectors::OrderBlocks`,
   `Detectors::Liquidity`.
2. For each detector's output, compare against the **last persisted `SmcEvent` of that
   `event_type`** for this instrument's correlation_id (a DB query, not a Redis blob — the
   event log itself is the state) to decide whether this represents a genuinely new event
   (e.g. a new swing high price, a BOS that didn't exist before, a new active FVG) or a
   repeat of already-known state.
3. For each new event, call `EventStore::Publisher.publish!` with:
   - `stream:` `"SMC-STRUCTURE"` (fixed value, distinguishes from other streams sharing the
     table)
   - `event_type:` one of `swing_high`, `swing_low`, `bos`, `choch`, `fvg_created`,
     `order_block_formed`, `liquidity_sweep`
   - `correlation_id:` `"SMC-STRUCT-#{symbol}-#{interval}"` — **stable per instrument**, not
     a random UUID, so `sequence` accumulates as one continuous chronological history per
     symbol/interval. (Composite "signal" events keep their existing per-call random UUID
     scheme — that's an unrelated concern and is not touched.)
   - `payload:` detector output fields plus `parent_event_id:` (nullable, references
     another `SmcEvent.id`), e.g.:
     - CHoCH → `parent_event_id` = the BOS event it reversed
     - `liquidity_sweep` → `parent_event_id` = the swing event whose level was taken
     - `fvg_created` → no parent (origin event)
4. `validate_contract: false` — the existing JSON-schema validation in
   `EventStore::Publisher` only applies to `event_type: 'signal'`; atomic structure events
   are a different shape and skip it (matches existing `signal_event?` guard behavior — no
   change needed there).

### Wiring

Called from `Smc::Scanner`'s existing per-symbol loop, alongside (not replacing) the
current `TradingSignalContract.publish!` call. Additive — the existing signal path is
unchanged.

### Deletions

- `app/services/smc/analyzer.rb` — dead code, zero callers.
- `app/services/smc/structure_store.rb` — dead code, only reachable via the above.
- Corresponding spec files if present.

### Testing

- **Dedup:** feeding the same detector output twice produces no duplicate `SmcEvent` row.
- **Parent-ref correctness:** a CHoCH event's `parent_event_id` resolves to the correct
  prior BOS event; a sweep's resolves to the correct swing event.
- **Replay determinism:** replaying the same series through `StructureEventRecorder` twice
  (fresh correlation_id namespace each time, e.g. test-specific symbol) produces identical
  event sequences — reuses existing `EventStore::ReplayEngine`, no changes needed there.
- **Sequence ordering:** multiple `record!` calls across simulated time produce
  monotonically increasing `sequence` within the same `correlation_id`.

### Explicitly out of scope

- Reviving `Smc::Analyzer`'s phase state machine (Trap → Expansion → Trend → Entry Zone) —
  not requested, would be new scope beyond "make structure events append-only."
- Any change to `TradingSignalContract`'s composite signal event or its correlation_id
  scheme.
- Any change to the `smc_events` table schema, `EventStore::Publisher`, or
  `EventStore::ReplayEngine` — all reused as-is.
