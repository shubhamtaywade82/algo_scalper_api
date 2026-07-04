# Option Chain Scalper View — Live ATM±5 Chain + Greeks Dashboard

**Date:** 2026-07-04
**Approach:** New `Options::ChainWatchService` + `OptionChainChannel`, new SolidJS view reusing existing feed/positions infra
**Branch:** `feature/options-buying-improvements`

## Context

The system runs fully autonomous NIFTY/BANKNIFTY/SENSEX options scalping, but has no live view for a trader to *watch* naked-option-buying signals manually: underlying spot, ATM±5 strike option chain (OI, IV, greeks), and current positions/orderbook, all updating in real time in the dashboard.

Existing infra already covers most of the primitives, so this is an integration/extension task, not greenfield:

- `Live::MarketFeedHub` (Singleton) — WS tick subscribe/unsubscribe per security_id, ticker or full-depth mode.
- `Live::TickCache` / `Live::TickQuery` — authoritative live LTP/OI read boundary.
- `Options::ChainAnalyzer` / `Adapters::OptionChain::DhanAdapter#fetch_chain` — REST option-chain pull with OI/IV/greeks per leg.
- `Derivatives::AtmOptions.call(symbol:, atm:, range:)` — static ATM±N strike selection (Postgres `Derivative` rows: security_id, strike, option_type — no live data).
- `DashboardChannel` / `PositionsChannel` (ActionCable, Solid Cable backend) — existing batched WS push pattern (`Live::PnlUpdaterService` broadcasts every 250ms).
- `dashboard/src/stores/usePositions.js` — existing WS+poll-merge pattern with staleness detection, and `OpenPositions.jsx`/`PositionRow.jsx` components already render live positions.
- `docs/OPTIONS_RESEARCH/implementation_plan.md` — documents an **"Event-Driven Sniper Subscription" doctrine**: only the underlying/VIX stay always-subscribed (compact mode); full 20-level market depth is reserved for the single actively-traded leg, subscribed only after signal trigger, unsubscribed on exit. Continuously subscribing ATM±N strikes in full-depth mode would violate this doctrine and add unnecessary WS load.

No existing service assembles a live "ATM±5 chain with OI/IV/greeks" view, and no channel pushes option-chain data to the frontend today. IV data is otherwise only captured once/day at ATM via `IvSnapshot`/`IvSnapshotJob` — not live, not per-leg.

## Scope

- Indices: NIFTY, BANKNIFTY, SENSEX
- Strikes: ATM ±5 (11 strikes, CE+PE) per index, nearest expiry only
- Live LTP: WS ticker/compact mode (not full depth) — consistent with the Sniper doctrine
- OI/IV/greeks: REST poll, staggered per index (3-5s cadence, respects Dhan's 1 req/sec quote-API limit)
- Positions/orderbook panel: reuse existing `OpenPositions`/`PositionRow` + `PositionsChannel` — no new backend for this part
- Subscription lifecycle: WS legs subscribed only while the view has an active channel subscriber; unsubscribed when the last viewer disconnects
- Out of scope: automated order placement, full market depth on ATM±5 legs, pending-order (as opposed to position) query service, any index beyond the three named, any expiry beyond nearest

## Design

### Architecture

```
Live::MarketFeedHub (existing, ticker mode)   ──┐
  underlying + ATM±5 CE/PE LTP subscribe         ├──> Options::ChainWatchService ──> per-index cache ──> OptionChainChannel (batched ~1s) ──> SolidJS view
                                                  │
Options::ChainAnalyzer / DhanAdapter REST poll  ─┘   (OI, IV, greeks per leg, staggered 3-5s per index)

Existing PositionsChannel + OpenPositions component ──> reused as-is for the positions/orderbook panel
```

### Backend: `Options::ChainWatchService`

One instance per index (NIFTY/BANKNIFTY/SENSEX), lifecycle tied to `OptionChainChannel` subscription (started on first subscriber, stopped when the last one disconnects — mirrors how position-scoped WS subscriptions are already gated elsewhere in the codebase):

1. Resolve ATM from `Live::TickQuery.for_security` (underlying) or REST fallback if cache miss, matching the pattern already used in `Options::DerivativeChainAnalyzer#spot_ltp`.
2. `Derivatives::AtmOptions.call(symbol:, atm:, range:)` → static ATM±5 leg rows (security_id, strike, option_type).
3. `Live::MarketFeedHub.instance.subscribe_many` for underlying + all resolved legs, ticker mode.
4. Background timer polls `Options::ChainAnalyzer`/`DhanAdapter#fetch_chain` every 3-5s, staggered across the three index services so REST calls don't collide against the 1 req/sec quote-API limit.
5. Merges live tick LTP (`Live::TickQuery`) with REST OI/IV/greeks into a per-index, per-expiry cache (Redis, consistent with `Live::TickCache`'s write-through pattern — avoids re-fetching REST state on every WS push).
6. Re-checks ATM each poll cycle; if it shifts enough to change the ±5 band, diffs old/new strike sets and calls `subscribe`/`unsubscribe` on `MarketFeedHub` for the changed legs only.
7. On last channel subscriber leaving, calls `unsubscribe` for all legs it added — WS budget returns to baseline.

### Backend: `OptionChainChannel`

New ActionCable channel, `stream_from "option_chain_#{index_key}"`. Broadcasts merged chain state (spot, ATM, per-leg LTP/OI/OI-change/IV/greeks/last-updated) at a throttled ~1s cadence — option-chain data moves slower than PnL, so this can be less aggressive than `PositionsChannel`'s 250ms. `subscribed`/`unsubscribed` callbacks start/stop the corresponding `Options::ChainWatchService` instance for that index.

### Frontend

- New view `dashboard/src/views/OptionScalper.jsx`, route `/option-scalper` added in `App.jsx`, nav entry in `Header.jsx`.
- New store `dashboard/src/stores/useOptionChain.js` — same WS+poll-merge/staleness pattern as `usePositions.js` (subscribes `OptionChainChannel` per selected index via `cable.js`, marks data stale past a threshold with no update).
- New component `OptionChainTable.jsx` — strike rows × CE/PE columns (LTP, OI, OI∆, IV, delta), ATM row highlighted.
- Positions/orderbook panel: embed existing `OpenPositions` component directly — no new component or backend needed here per scope decision.
- Index selector (NIFTY/BANKNIFTY/SENSEX tabs) drives which `OptionChainChannel` stream the store subscribes to; switching tabs unsubscribes the old stream and subscribes the new one (keeps only one index's `ChainWatchService` warm per open browser tab, though multiple tabs/indices can be active system-wide).

### Error Handling

- WS feed gap: if `Live::TickQuery` returns nil/stale past a threshold for a subscribed leg, mark that leg `feed_stale: true` in the broadcast payload; frontend renders a stale badge instead of freezing the last number silently.
- REST chain poll failure (rate-limit/network): log, keep last-known OI/IV/greeks, mark `chain_stale: true` after consecutive-failure threshold.
- ATM shift resolution failure (new strike not found in `Derivatives::AtmOptions`): log and skip that leg only, don't crash the index's `ChainWatchService`.
- Channel disconnect/reconnect: `unsubscribed` callback must reliably tear down `MarketFeedHub` subscriptions to avoid leaking WS subscriptions across reconnects — guard with idempotent unsubscribe.

### Testing

- RSpec unit tests for `Options::ChainWatchService`'s merge logic (tick update, REST chain update, ATM-shift leg diffing) using fixture ticks/chain payloads — no live API dependency, follows existing repo test conventions (`docs/development/testing.md`).
- RSpec channel test for `OptionChainChannel` subscribe/unsubscribe lifecycle (service start/stop wiring), mocking `Options::ChainWatchService`.
- Manual smoke test during market hours: verify all three indices populate, ATM/greeks look sane, tab switching correctly subscribes/unsubscribes, positions panel unaffected. No automated live-market integration test, consistent with existing project convention for feed-dependent behavior.
