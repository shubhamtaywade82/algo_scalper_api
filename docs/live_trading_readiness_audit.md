# Live Trading Readiness Audit

## Review Procedure
1. Trace index option discovery from cache lookup through strike selection and order queuing.
2. Inspect live position reconciliation, tracker hydration, and exit automation wiring.
3. Compare allocator guardrails with runtime risk loop thresholds and circuit breakers.
4. Verify broker connectivity toggles, feed health guards, and operational fallbacks for exits.

## Readiness Summary
| Area | Status | Notes |
| --- | --- | --- |
| Instrument Mapping | ❌ | Cache normalises segments; importer stores raw codes, so picks lack SIDs. |
| Position Coverage | ❌ | Sync downcases exchange codes and never matches stored contracts. |
| Risk Controls | ⚠️ | Risk loop exits at 1% loss while allocator budgets 2.5–5%. |
| Feed Health | ⚠️ | Entry guard logs outages but never blocks on stale feeds. |
| Exit Path | ⚠️ | Exit orders abort whenever the positions snapshot call fails. |

> **Warning:** Launching with the current defaults will fail to place option buys and will
> leave broker lots unmanaged when DhanHQ returns data with lowercase-sensitive fields.

## Critical Findings
### Index Instrument Cache Loses Derivative Links
`IndexInstrumentCache` converts configured index segments into `"index"` before querying the
store, but the importer persists the raw segment code such as `"I"`.【F:app/services/index_instrument_cache.rb†L63-L90】【F:app/services/instruments_importer.rb†L85-L148】
When the lookup fails, the cache returns an unsaved instrument without derivatives, causing the
strike filter to build legs with `security_id: nil` that still pass to the entry guard.【F:app/services/options/chain_analyzer.rb†L277-L316】 Because the entry guard forwards the
`security_id` unchecked, the placer raises and the trade never leaves the app.【F:app/services/entries/entry_guard.rb†L43-L66】

### Position Sync Cannot Rehydrate Broker Lots
The market stream disables the order-update WebSocket and relies on `Live::PositionSyncService`
to poll DhanHQ for open positions.【F:config/initializers/market_stream.rb†L25-L48】 The sync
routine downcases exchange and segment codes before querying our tables, so no derivative or
instrument records are found, and trackers are never created for broker-side lots.【F:app/services/live/position_sync_service.rb†L98-L189】 All such exposures stay unmanaged,
including their stops.

### Risk Limits Conflict With Capital Policy
Runtime risk checks treat a 1% price move against the option debit as a hard exit, regardless of
the configured 30% stop.【F:config/algo.yml†L27-L34】【F:app/services/live/risk_manager_service.rb†L185-L210】 Capital allocation budgets 2.5–5% of account equity per trade depending on
balance bands, so the system flattens trades long before the intended risk budget is consumed.【F:app/services/capital/allocator.rb†L9-L55】 This disconnect undermines allocator guardrails.

### Feed Health Not Enforced On Entries
Entry flow only logs WebSocket outages and proceeds with REST fallbacks; it never asserts feed
freshness before placing orders.【F:app/services/entries/entry_guard.rb†L17-L33】 No component calls
`FeedHealthService.assert_healthy!`, so stale funds or position feeds cannot block new risk.【4c8b29†L1-L4】

### Exit Orders Abort On Position Snapshot Failures
Exit placement depends on fetching fresh position details from DhanHQ; any error there returns
`nil` and the placer abandons the order.【F:app/services/orders/placer.rb†L143-L227】 The risk manager
treats an unsuccessful placement as fatal and leaves the tracker active without retrying, even
though the loss trigger already fired.【F:app/services/live/risk_manager_service.rb†L451-L468】

## Recommendations
- Align segment handling between the importer, cache, and strike selector so every pick carries
  a valid `security_id`.
- Normalise exchange codes in `PositionSyncService` to the stored uppercase form and persist the
  broker-reported side.
- Reconcile allocator and risk-loop thresholds and reinstate the daily loss breaker before
  enabling production mode.
- Enforce `FeedHealthService` gates on entry flow and fail fast when feeds are stale instead of
  silently falling back.
- Add retries or cached snapshots around exit placement so triggered stops are not skipped by
  transient API faults.
- Document that `ENABLE_ORDER=true` is required for live execution and pair it with a distinct
  `ENABLE_EXECUTION` flag.
