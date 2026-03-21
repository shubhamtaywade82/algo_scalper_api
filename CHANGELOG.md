# Changelog

## 2026-03-21
- **Market context (alpha):** Add `MarketContext::RegimeSnapshot`, `RegimeComposer`, `StructureAnalyzer`, `VolatilityAnalyzer`, and `ParticipationAnalyzer` under `app/services/market_context/`. Composes existing `MarketRegimeDetector` with candle/VWAP/volume signals and a weighted `conviction_score` from `config/algo.yml` (`market_context.regime_scoring`).
- **Chain signal (alpha):** Add `Options::ChainSignalExtractor` (`app/services/options/chain_signal_extractor.rb`) using raw `chain_data` + `Options::FlowAnalyzer` history (PCR, flow scores, ATM premium expansion vs cache). Does not modify `Options::ChainAnalyzer`.
- **Permission gate (alpha):** Add `Trading::MarketPermissionGate` (`app/services/trading/market_permission_gate.rb`); optional hard block after strike qualification in `Signal::Engine#evaluate_market_context_for_entry` when `market_context.gate.enabled` is true. Structured log `entry_blocked` with `stage: market_permission_gate`.
- **Strategy profiles:** Add `Trading::StrategyProfileSelector`; `strategy_profile` and market/chain diagnostics merge into `entry_metadata` and persist on `PositionTracker.meta` via `Entries::EntryGuard` diagnostic merge.
- **Trailing:** `Trading::TrailingEngine#config_for_symbol` merges `risk.institutional_trailing.profiles.<strategy_profile>` when `tracker.meta['strategy_profile']` is set.
- **Config:** New `market_context:` and `institutional_trailing.profiles` sections in `config/algo.yml` (defaults keep feature off: `market_context.enabled: false`, `gate.enabled: false`).
- **Specs:** `spec/services/market_context/`, `chain_signal_extractor_spec`, `market_permission_gate_spec`, `strategy_profile_selector_spec`, `signal/engine_market_context_spec`, trailing profile example in `trailing_engine_spec`.
- **Autoload / naming:** Move `Strategies::ExpiryModel` to `app/models/strategies/expiry_model.rb` for Zeitwerk. Rename dev Redis key browser from `Redis::Inspector` to `RedisUi::Inspector` (`app/services/redis_ui/inspector.rb`) to avoid clashing with the `redis` gem’s `Redis` class; `RedisUiController` updated.

## 2026-03-12
- Enforce `PLACE_ORDER` as the required live broker execution toggle in `Orders::Placer`; live BUY/SELL/EXIT calls are blocked unless `ENV['PLACE_ORDER'] == 'true'`.
- Add explicit blocked-order warning logs for live placement attempts when `PLACE_ORDER` is disabled.
- Update order-placement specs and docs to reflect `PLACE_ORDER` as the canonical live-order safety gate.

## 2026-03-04
- Consolidate root-level ad-hoc markdown reports into `docs/reports/`.
- Add canonical documentation entrypoint `docs/index.md` and simplify `docs/README.md` to point to it.
- Move code-review backlog to `docs/reports/TODO.md`.
- Update CI Brakeman step to use `--no-exit-on-warn` so advisory warnings are reported without failing the pipeline.
- **Design patterns:** Unify live gateway on `Orders::GatewayLive`; add `flat_position` and `position` to GatewayLive; deprecate `Live::Gateway` (delegates to GatewayLive, logs deprecation warning).

## 2026-02-25
- Add `MarketTick` + `Live::TickQuery` boundary and migrate key risk/entry/exit reads off direct `Live::TickCache` access.
- Migrate remaining service/model `Live::TickCache.ltp` reads to `Live::TickQuery` so `TickQuery` is the sole LTP read boundary.
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
