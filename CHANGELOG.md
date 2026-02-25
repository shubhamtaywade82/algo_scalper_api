# Changelog

## 2026-02-25
- Route `Instrument` option-chain broker calls through injectable adapters and wire `NullAdapter` in paper mode.
- Implement `cancel_order` in `Live::Gateway` to keep parity with the `Orders::Gateway` cancel contract used by risk-manager flows.
- Route risk-manager order cancel operations through the `Orders::Gateway` port and add gateway cancel support for live/paper adapters.
- Cache `RiskManagerService` config at initialization to avoid repeated `AlgoConfig.fetch` calls during risk checks.
- Add startup broker reconciliation in trading daemon boot path via `Live::PositionSyncService` before service startup, with strict mode during market hours.
- Add durable exit intent fields (`exit_requested_at`, `exit_sent_at`, `exit_coid`, `exit_order_id`) and deterministic exit correlation IDs to improve retry safety.
- Update exit routing/gateway flow to pass client order IDs explicitly and normalize already-closed/duplicate exit responses as successful terminal outcomes.
- Add `docs/runbooks/paper_mode_durability.md` operator runbook with staged paper-mode durability checks, kill-9 restart drills, and pre-live sign-off criteria.

## 2025-02-16
- Document live trading readiness audit covering instrument mapping, position sync, risk,
  feed health, and exit reliability gaps.

## 2025-02-15
- Document options-buying readiness, risk flow, and configuration switches in the README.

## 2025-02-14
- Ensure `Signal::Scheduler` runs as a singleton to prevent duplicate signal threads and add graceful shutdown.
- Replace `defined?` guards in the market stream initializer with explicit class usage and NameError fallbacks.
