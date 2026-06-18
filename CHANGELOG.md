# Changelog

## 2026-06-18

### Trading — Stock Supertrend options buyer cleanup

- Trimmed default exit wiring to hard stop, four-stage adaptive premium trail, fixed take profit, and time close.
- Added objective chop scoring before 1m Supertrend entries.
- Disabled advanced options-buying gates by default: compression, breakout arming, chain radar streams, RSI bias, expiry-week power trend, profit floor, RR exits, premium momentum failure, time stop, and institutional/direct trailing.

## 2026-04-06

### Documentation — Align with AlgoConfig and signal engine (post run_mode removal)

- **README.md**, **AGENTS.md**, **CLAUDE.md**, **REPO_SUMMARY.md** — Document merge order
  (YAML → DB → `signal_tier_presets.yml` → `LIVE_TRADING`), `SIGNAL_TIER`, and live gates
  (`dhanhq.enable_orders`, `PLACE_ORDER`).
- **docs/development/guides/setup.md**, **docs/development/deployment.md**,
  **docs/development/testing.md**, **docs/development/testing_profiles.md** — Remove stale
  `RUN_MODE` / `exit_testing` / `config/profiles` instructions; replace with tier + env
  guidance.
- **docs/diagrams/trading-modes.md** — Rewritten for current `AlgoConfig.fetch` and single
  `Signal::Engine` pipeline.
- **docs/trading/signal_engine.md**, **docs/trading/trading-pipeline.md**,
  **docs/services/signal_services.md**, **docs/architecture/execution-flow.md**,
  **docs/architecture/system_overview.md**, **docs/architecture/component-map.md** —
  Updated steps (halt, no-trade, DTE, `effective_validation_mode`, `options_analysis_gate`);
  restored full guard/exit sections in execution-flow where needed.
- **docs/integrations/dhanhq-api.md** — Gateway selection documents effective
  `paper_trading.enabled`.
- **docs/trading/entry_and_exit_rules.md** — Lunch relaxation note uses tiers/YAML, not
  `exit_testing`.
- **docs/options/SYSTEM_STATE.md**, **docs/options/README.md** — Refreshed against current
  engine and config knobs.

## 2026-03-31

### Documentation — Comprehensive accuracy update (all docs rewritten)

- **README.md** — Rewritten: updated tech stack (Ollama replaces OpenAI, Next.js dashboard instead of Vue/Vite), corrected entry guard pipeline from 10 guards to 20 guards, added `ExpiryWeekPowerTrendGuard` and `LossStreakGuard` details, added `PLACE_ORDER` env var requirement, added run modes section, corrected `midday_guard.trending_adx_bypass: 28` note, removed stale Docker Compose dashboard claim.
- **REPO_SUMMARY.md** — Rewritten: reflects 20-guard pipeline, Ollama AI client, market_context optional layer, `run_mode` system, full guard pipeline table, correct profile file locations.
- **docs/architecture/system_overview.md** — Updated: added run modes table and profile system, corrected AI section (Ollama, `ollama-client` gem), clarified `PLACE_ORDER` dual safety gate, updated startup sequence.
- **docs/architecture/component-map.md** — Rewritten: full 20-guard pipeline table with positions, added `ExpiryWeekPowerTrendGuard` details, corrected guard numbering, added market context optional layer component group, updated AI layer section.
- **docs/architecture/execution-flow.md** — Rewritten: full 20-guard table with descriptions, step-by-step signal engine pipeline matching actual `Signal::Engine` 13-step structure, `ExpiryWeekPowerTrendGuard` documentation, `PLACE_ORDER` safety gate details.
- **docs/trading/trading-pipeline.md** — Rewritten: full pipeline with all 8 stages, `ExpiryWeekPowerTrendGuard` pattern description in guard stage, run mode behavior table.
- **docs/trading/entry_and_exit_rules.md** — Updated: new guards (DrawdownGuard, EntryPolicyGuard, LossStreakGuard, MaxConcurrentGuard, SizingGuard, RiskPolicyGuard, SmcNavigatorGuard, WeeklyExpiryGuard, BosStructureGuard) added to pipeline table; `ExpiryWeekPowerTrendGuard` (guard 11) details; `DECIMAL format` note on all config values.
- **docs/trading/signal_engine.md** — Rewritten: matches actual `Signal::Engine` 13-step structure, run mode behavior table, exit_testing forced overrides documented, market context optional section updated.
- **docs/trading/risk_management.md** — Updated: added `LossStreakGuard` and `DrawdownGuard` to safety mechanisms, clarified `persist_final_pnl_from_cache` recalculation (actual PnL not stale Redis snapshot), added time-based exit section.
- **docs/services/service-catalog.md** — Rewritten: Ollama AI services (removed OpenAI references), full 20-guard guard list, market context services, `ExpiryWeekPowerTrendGuard` entry, `PLACE_ORDER` safety gate note in `GatewayLive`, correct `Positions::TrailingConfig` DECIMAL defaults.
- **docs/development/deployment.md** — Rewritten: added `PLACE_ORDER` env var requirement, `RUN_MODE` override, WSL2 memory note, Ollama env vars, correct process management commands, pre-live checklist updated.
- **docs/development/testing.md** — Rewritten: replaced adaptive-exit-system-only guide with comprehensive testing reference covering test suite structure, paper trading validation, Rails console queries, exit rule testing, drawdown verification, circuit breaker testing, troubleshooting.
- **docs/trading/safety_mechanisms.md** — Updated: added `LossStreakGuard`, `DrawdownGuard`, `ExpiryWeekPowerTrendGuard`, `Portfolio::DrawdownGuard`/`ProfitLockEngine`, `PLACE_ORDER` dual safety gate, exit intent durability, PnL integrity fix documentation.
- **docs/trading/market_context_and_permission_gate.md** — Minor updates: added component analyzer details, config YAML example.
- **docs/trading/order-execution-flow.md** — Rewritten: `PLACE_ORDER` safety gate requirement, paper vs live flow comparison, `exit_coid` durability, full order state lifecycle.
- **docs/services/live_services.md** — Updated: added `PnlUpdaterService` section, `TrailingEngine` modes, `EdgeFailureDetector` trigger conditions, `StatsNotifierService` cadence.
- **docs/services/signal_services.md** — Updated: run mode behavior table, `Signal::MomentumValidator` section, `IndexInstrumentCache` section, `max_expiry_days` config note.
- **docs/services/risk_services.md** — Updated: `PercentagePnlRule` DECIMAL note, `TrailingConfig` DECIMAL defaults, `Portfolio::DrawdownGuard`/`ProfitLockEngine` documentation.
- **docs/services/order_services.md** — Updated: `PLACE_ORDER` requirement in `GatewayLive`, `ExpiryWeekPowerTrendGuard` context enrichment in `EntryGuardPipeline`, `MfeExitEngine` and `ExpiryRuleEngine` sections.
- **docs/integrations/dhanhq-api.md** — Updated: `PLACE_ORDER` safety gate, correct segment/security_id table for NIFTY/BANKNIFTY/SENSEX, token 3-tier details.
- **docs/market-data/market-data-flow.md** — Updated: corrected Sidekiq reference removed (Solid Queue), added `TickQuery` read boundary section, latency profile table.
- **docs/architecture/websocket-feed.md** — Updated: Next.js dashboard reference, `TickQuery` nil-on-miss critical invariant, order update WebSocket section.
- **docs/development/testing_profiles.md** — Updated: `Signal::Engine` behavior by mode table, `exit_testing` forces `supertrend_adx`/`1m` in engine, safety notes for live mode, current default (`exit_testing`) noted.

### Code changes incorporated into documentation

- **AI layer**: `ruby-openai` and `openai` gems removed; `ollama-client ~> 1.1` is now the sole AI provider. `lib/services/ai/ollama_client.rb` wraps `Ollama::Client` with chat, generate, streaming, model auto-selection.
- **Entry guard pipeline**: Expanded from 10 guards to 20 guards. New guards include `DrawdownGuard`, `EntryPolicyGuard`, `LossStreakGuard`, `MaxConcurrentGuard`, `SizingGuard`, `RiskPolicyGuard`, `SmcNavigatorGuard`, `WeeklyExpiryGuard`, `BosStructureGuard`, and `ExpiryWeekPowerTrendGuard`.
- **`ExpiryWeekPowerTrendGuard`**: New guard (position 11) — detects ADX >= 40 + within 5 days of monthly expiry + 12:00-13:45. Enriches `context[:expiry_power_trend]`; never blocks. `TimeRegimeGuard` (position 12) bypasses S3 chop-zone block when flag is set.
- **`LossStreakGuard`**: New guard blocking on consecutive losses >= `loss_streak_guard.consecutive_losses_threshold` (default 2).
- **`PLACE_ORDER`** env var: Safety gate in `Orders::Placer` — live BUY/SELL/EXIT blocked unless `PLACE_ORDER=true`.
- **Run modes**: `run_mode: production | exit_testing | entry_testing` in `config/algo.yml`; profile files in `config/profiles/`; `AlgoConfig.run_mode` accessor. Current default: `exit_testing`.
- **`persist_final_pnl_from_cache`**: Recalculates `last_pnl_pct` from `final_pnl / (entry_price * quantity)` — not stale Redis snapshot — fixing PnL mismatch at exit.
- **Dashboard**: Next.js (not Vue/Vite as previously documented).

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
