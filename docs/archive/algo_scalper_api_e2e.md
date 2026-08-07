# algo_scalper_api — End-to-End System Reference

Purpose of this doc: complete, code-verified reference for feeding into an AI
research chat (strategy research, architecture Q&A, risk analysis). Compiled
directly from source (Gemfile, routes.rb, bootstrap.rb, algo.yml, schema.rb,
service directory) as of 2026-07-17, branch `cleanup-complexity-v3`. Repo docs
under `docs/` (150+ files) are historically stale in places — this reflects
actual current wiring, not those docs.

---

## 1. What it is

Rails 8 API-only backend for **fully autonomous intraday options scalping**
on Indian index derivatives (NIFTY, BANKNIFTY, SENSEX). One process generates
signals, qualifies option strikes, sizes capital, places orders via DhanHQ,
and manages exits — no human in the loop during market hours. Paper and live
modes share the same logic; only order execution differs.

## 2. Stack

| Layer | Tech |
|---|---|
| Language/Framework | Ruby 3.3.4, Rails 8.1.3 (API-only) |
| DB | PostgreSQL |
| Cache/state | Redis (ticks, PnL, positions, circuit breaker) |
| Job queue | Solid Queue (NOT Sidekiq) |
| WebSocket broadcast | Solid Cable (ActionCable backend) |
| Rails.cache | Solid Cache |
| Broker | DhanHQ v2, gem `DhanHQ` 2.8.0 (`require: 'dhan_hq'`) + `dhanhq-mcp` (local path gem) |
| AI (local) | `ollama-client` ~> 1.1 — no OpenAI/ruby-openai anywhere |
| Multi-agent framework | `ruby_llm-agents` gem (mounted at `/agents`, RubyLLM::Agents::Engine) |
| Notifications | `telegram-bot-ruby` ~> 0.19 |
| Rate limiting | `rack-attack` (per-IP throttling on expensive `/api` routes) |
| TOTP | `rotp` (Dhan token auto-refresh) |
| Frontend | Next.js dashboard, separate process, separate repo dir (`dashboard/`) |

## 3. Process model

`./bin/dev` (foreman) runs `Procfile.dev`, 4 OS processes sharing only
Postgres + Redis (no shared in-process state):

| Process | Command | Role |
|---|---|---|
| `web` | `bin/rails server -p 3011` | API server, dashboard data, ActionCable |
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | The trading brain — ~19 services as threads |
| `jobs` | `bin/jobs` | Solid Queue worker — recurring + one-off jobs |
| `dashboard` | `cd dashboard && npm run dev` | Next.js frontend |

Standalone equivalents:
```bash
bin/jobs
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

## 4. Trading daemon — actual service registry

Source of truth: `lib/trading_system/bootstrap.rb` → `build_supervisor`
(NOT the older 11-service table still quoted in `README.md` and
`docs/architecture/system_overview.md` — both are stale; `Signal::Scheduler`
is no longer registered at all, replaced by `Strategies::Manager`).

| Key | Class | Cadence / trigger |
|---|---|---|
| `:market_feed` | `Live::MarketFeedHubService` | Event-driven (DhanHQ WS) |
| `:tick_smc_ai` | `Smc::TickAi::AnalysisService` | Per-tick |
| `:options_buying_breakout` | `OptionsBuying::BreakoutWatcher` | Event/interval |
| `:options_buying_stream_consumer` | `OptionsBuying::StreamConsumer` | Redis stream consumer |
| `:risk_manager` | `Live::RiskManagerService` | 5s enforcement loop + per-tick EventBus |
| `:position_heartbeat` | `TradingSystem::PositionHeartbeat` | 10s |
| `:order_router` | `TradingSystem::OrderRouter` | On-demand |
| `:paper_pnl_refresher` | `Live::PaperPnlRefresher` | 1s (paper only) |
| `:exit_manager` | `Live::ExitEngine` | On-demand (single source of truth for exits) |
| `:active_cache` | `Positions::ActiveCacheService` | On-demand |
| `:reconciliation` | `Live::ReconciliationService` | 30s |
| `:stats_notifier` | `Live::StatsNotifierService` | Market close |
| `:smc_scanner` | `Smc::Scanner` | 5 min |
| `:strategy_manager` | `Strategies::Manager` | 2s control loop + per-strategy runner threads |
| `:pnl_updater` | `Live::PnlUpdaterService` | 250ms flush |
| `:candle_poller` | `Live::CandlePollerService` | Polling |
| `:chain_watch_nifty` / `_banknifty` / `_sensex` | `Options::ChainWatchService` | Per-index; skipped gracefully if index disabled in DB watchlist |

Boot sequence (`Bootstrap.boot_reconciliation!`, `boot_market_gates!`):
1. Rails initializers wire DhanHQ config, gateway (paper/live), token bootstrap.
2. `Live::PositionSyncService.instance.force_sync!` — reconcile DB vs broker before anything else starts (raises if `strict: true`).
3. `Market::VixGate.evaluate!` at boot (so a late daemon start doesn't fail-open on VIX entry gating until the next 15-min job).
4. `supervisor.start_all`.

## 5. Two competing/complementary signal-generation paths

This is the most important thing an outside reviewer will miss from the repo
docs: there are **two live signal pipelines**, not one.

### 5a. Legacy path — `Signal::Engine` (still present, still ALPHA layer, but its scheduler is not registered as a daemon service anymore)
`app/services/signal/engine.rb` (Supertrend + ADX + regime detection) and
`app/services/signal/scheduler.rb` exist and are fully wired for use, but
`Strategies::Manager` — not `Signal::Scheduler` — is what's registered in
`bootstrap.rb` today. Confirm current invocation path in code before assuming
`Signal::Scheduler`'s 30s loop is what's driving entries; the manager comment
explicitly says it "Replaces Signal::Scheduler with per-strategy lifecycle
management."

### 5b. Current path — `Strategies::Manager` plugin platform
`app/services/strategies/manager.rb`: one control thread (2s) reconciles
`Strategies::Record` rows (desired vs actual), spins a runner thread per
`running`/`deployed` strategy, feeds it `Core::EventBus :candle_closed`
events. Each runner:
1. Builds context via `Strategies::ContextBuilder`.
2. Calls `strategy.call(context)` → a `Signals::{BuyCall,BuyPut,Hold,Exit}` object.
3. Persists a `Strategies::Signal` row (shadow by default).
4. If action is `buy_call`/`buy_put` **and** `strategy_platform.auto_entry_enabled`
   (algo.yml) **and** confidence ≥ `min_confidence` (default 0.6): resolves
   index config → `Options::ChainAnalyzer.pick_strikes` → loops candidate
   strikes through `Entries::EntryGuard.try_enter` until one succeeds.
5. Crash handling: exponential backoff (2^errors, cap 60s), auto-stop after
   5 errors in a 10-min window → strategy marked `errored`.
6. Heartbeats every 10s, broadcasts to ActionCable `strategy_status` channel.

Strategy plugins live under a `Strategies::Base` subclass contract (see
`app/services/strategies/base.rb`, `loader.rb`, `discovery.rb`). Reference
design docs: `docs/infra-strategy-setup/00_overview.md` through `10_...md`
(these are the current/forward-looking design set, unlike the stale
top-level docs).

Both paths funnel into the same downstream: `Options::ChainAnalyzer` →
`Entries::EntryGuard` → `Capital::Allocator` → `Orders` gateway →
`PositionTracker`.

## 6. Options-buying framework (separate, config-driven strategy layer)

`app/services/options_buying/` — a large, mostly independent strategy engine
(`config/algo.yml: options_buying`) with its own strategies under
`options_buying/strategies/`: `orb_breakout`, `vcp_breakout`,
`triple_tf_alignment`, `vix_expansion`, `iv_percentile_confluence` (toggled
in `options_buying.strategies.enabled`). Supporting pieces:

- `chain_radar.rb` — periodic option chain scan (delta 0.45–0.55 band, min volume, refresh 30 min)
- `breakout_watcher.rb` / `breakout_evaluator.rb` — 1m breakout detection with volume multiplier + OI unwind confirmation
- `atr_compression` (config) — compression setup detector, ATR period 14, arms before 11:15
- `gamma_wall_detector.rb` — OI-based gamma wall with buffer
- `vix_filter.rb` — blocks buying outside VIX 12–30 band or on fast VIX drops
- `regime_classifier.rb`, `rsi_divergence_scanner.rb`, `expected_value_model.rb`, `trade_scoring_engine.rb`
- `carry_policy.rb` + `eod_carry_manager.rb` — optional **positional** mode: hold overnight only if min ROI 30%+, capped at 3 carries / ₹150k exposure
- `stream_consumer.rb` / `stream_writer.rb` — Redis Streams pipeline (`options_buying.streams`, consumer group `options_buying_evaluators`)
- `execution` config block: `spread_enabled` (BidAskSpreadGuard), `tcm_enabled` (TransactionCostGuard — pre-trade net-edge gate, off by default), `limit_chasing` (max 15s chase, 2s tick, fallback to market), `order_slicing` (500ms delay, per-index freeze limits)
- Mode switch: `options_buying.mode: intraday_scalper | positional` (see `docs/options_buying_intraday_spec.md`)

This is functionally a second strategy stack layered next to
`Strategies::Manager` / `Signal::Engine` — worth clarifying with the user
which one is the "primary" live strategy before making recommendations.

## 7. Entry Guard Pipeline

`app/services/entries/entry_guard.rb` orchestrates; `entry_guard_pipeline.rb`
runs the chain. Actual guard file count is **33**, not the 20 documented in
`README.md`/`CLAUDE.md`. Files under `app/services/entries/guards/`:

```
base_guard, drawdown_guard, entry_policy_guard, circuit_breaker_guard,
midday_quality_guard, edge_failure_guard, loss_streak_guard,
daily_limits_guard, max_concurrent_guard, global_max_concurrent_guard,
instrument_lookup_guard, ltp_resolution_guard, expiry_week_power_trend_guard,
time_regime_guard, weekly_expiry_guard, dte_entry_window_guard,
bos_structure_guard, exposure_guard, cooldown_guard, sizing_guard,
risk_policy_guard, smc_navigator_guard, chop_score_guard, regime_guard,
vix_gate_guard, iv_vol_gate_guard, momentum_gate_guard,
option_volume_velocity_guard, premium_band_guard, chain_confirmation_guard,
compression_setup_guard, breakout_ready_guard, segment_expectancy_guard,
index_trade_limit_guard, earliest_entry_guard, trading_time_restriction_guard
```
(Note: `BankniftyLastWeekGuard` named in old docs no longer exists as a
separate file — check current pipeline order in
`app/services/entries/entry_guard_pipeline.rb` rather than trusting any
prose list, this one included, for exact sequence/count.)

Guard responsibilities of note beyond the obvious:
- `expiry_week_power_trend_guard` — bypasses chop-zone blocking when ADX ≥ 40 within 5 days of monthly expiry, 12:00–13:45 window (documented rationale: near-ATM options can return 3–6x on a 0.8–1.4% spot move during expiry-week power trends)
- `segment_expectancy_guard` — blocks entries into a (index, session-regime) segment with realized negative expectancy over a 14-day lookback (min 8 samples to have an opinion)
- `loss_streak_guard` — 3 consecutive losses → 20 min cooldown

## 8. Capital, Orders, Exits (LOCKED infra — see §14)

- `Capital::Allocator` — rupee/percentage sizing; `capital_allocator.post_peak_size_cut` halves size once intraday peak ≥ ₹2k and current giveback exceeds 50% of peak.
- `Orders::GatewayFactory` picks `GatewayPaper` or `GatewayLive` **once at boot** (restart required to switch).
- `Orders::Placer` — idempotency + dry-run gate; live order submission requires **both** `algo.yml dhanhq.enable_orders: true` **and** `ENV PLACE_ORDER=true`.
- `Live::ExitEngine` — single source of truth for exit placement; `RiskManagerService` and `TrailingEngine` only *detect* conditions and call it.
- Exit evaluation is dual-path:
  - **Per-tick** (`realtime.tick_first_enabled`): `UnifiedExitChecker` off Redis-cached PnL, debounced `min_enforcement_gap_ms: 250`ms per tracker; falls back to interval scanning if tick stream stale > `tick_stale_after_seconds` (3s).
  - **5s enforcement loop**: premium R-stop, dynamic/gamma trailing, profit floor, structure invalidation, premium momentum failure, R:R booking, %PnL exit, time stop.
- `risk/rules/`: `stop_loss_rule`, `take_profit_rule`, `adaptive_trail_rule`, `time_stop_rule`, `time_decay_rule`, `iv_collapse_rule`, `structural_kill_switch_rule`, `zero_hwm_false_entry_rule`, run through `rule_engine.rb` + `rule_factory.rb`.

## 9. Ledger — double-entry paper accounting (parallel to legacy wallet math)

`app/services/ledger/` + tables `ledger_accounts`, `ledger_journal_entries`,
`ledger_postings`, `paper_daily_wallets`. Config (`algo.yml: ledger`):
```yaml
ledger:
  enabled: true          # paper wallet + sizing reads ledger cash balance
  paper_enabled: false   # legacy calc still authoritative; ledger posts for reconciliation only
  shadow_mode: true      # journals post, but ReconciliationJob just compares ledger vs legacy
  block_negative_cash: true
```
Recurring jobs: `Ledger::ReconciliationJob` (30 min), `Ledger::DailyCloseJob`
(3:35pm, rolls into `paper_daily_wallets`). See `docs/architecture/ledger.md`.

## 10. Research pipeline (offline, never touches live trading path)

`app/services/research/` + tables `research_signals`,
`research_option_candidates`, `research_option_bars`,
`research_premium_lifecycles`, `research_raw_fetches`, plus a newer
experiment-tracking set: `research_hypotheses`, `research_events`,
`research_event_strikes`, `research_event_exits`, `research_edge_registry`,
`research_experiment_registry`, `research_feature_registry`,
`research_feature_importances`, `research_dataset_snapshots`,
`research_data_quality_audits`.

- `Research::Pipeline.run` — single signal → ranked ATM±N candidates
- `Research::LifecycleRunner.run` — full board → ranked premium lifecycles (entry→peak→decay), tagged with `Research::ContextClassifier` regime labels (structure, trend strength, vol regime, momentum, volume regime, time-of-day, VWAP relation, liquidity sweep, ORB, gap) — reuses `Smc::Detectors::Structure`/`Liquidity` rather than re-deriving swing points
- `Research::ExpectancyReport.call` — groups persisted lifecycles by regime-label subsets → sample size / avg peak return / win rate / avg time-to-peak / avg drawdown, ranked — this is the actual "which context is worth trading" answer generator
- Recurring: `Research::DailyLifecycleJob` (NIFTY/BANKNIFTY/SENSEX) at 9:00am, auto-runs the prior session's board
- Dashboard: `/research` (Signal Pipeline / Premium Lifecycle Board / Context→Expectancy panels), API under `/api/research/*` (`routes.rb`: signals, lifecycles + `:run`, `:expectancy`)
- The presence of `research_hypotheses`/`research_experiment_registry`/`research_feature_registry` tables suggests a more formal hypothesis-tracking layer exists or is being built beyond what `CLAUDE.md`'s "Research Pipeline" section describes — worth asking the user directly what state that's in before relying on it.

## 11. AI / Agents layer (several distinct subsystems, not one)

- `app/services/ai/trading_bot/` — `engine`, `scanner`, `analyst`, `trader`, `notifier`, `self_learning`, `config` — looks like a semi-autonomous scan→analyze→trade loop with a self-learning component.
- `app/services/ai/trading_agent/` — `agent_loop`, `repl`, `prompt_builder`, `tool_registry`, `risk_validator`, `trace_logger`, `terminal_markdown` — an LLM tool-calling agent with its own REPL and audit trace.
- `app/services/ai/autonomous/` — `orchestrator`, `task_runner`, `auditor` — recurring job `Ai::Autonomous::OptimizationJob` (4:30pm daily) runs a self-learning "Observe-Think-Act" loop per index.
- `app/services/agents/trading_orchestrator.rb` + recurring `Agents::TradingSignalJob` (NIFTY/BANKNIFTY at open + every 30 min) — yet another AI-driven signal path, gated through `Ai::AlphaGate` / `Ai::GenerativeAiMarketGate`.
- `ruby_llm-agents` gem mounted at `/agents` (disabled in production unless `ENABLE_AGENTS_DASHBOARD=true`) — execution/cost tracking tables `ruby_llm_agents_executions`, `_execution_details`, `_overrides`.
- Local Ollama only (`ollama-client` gem) for `AiTechnicalAnalysisJob` — no external LLM provider in the codebase.

There is real overlap/redundancy risk across `ai/trading_bot`, `ai/trading_agent`,
`ai/autonomous`, and `agents/trading_orchestrator` — four AI-driven decision
surfaces exist side by side. Worth explicitly asking which are live vs
experimental/dead before reasoning about "the" AI strategy.

## 12. SMC (Smart Money Concepts)

`app/services/smc/` — `scanner.rb` (5-min supervisor service),
`bias_engine.rb`, `detectors/` (`fvg`, `order_blocks`, `liquidity`,
`structure`, `swing_structure`, `internal_structure`, `premium_discount` — 7
pure detectors), `confluence/` (multi-timeframe confluence engine: `engine`,
`mtf_digest`, `ltf_snapshot`, `bar_result`, `state`), `tick_ai/`
(`analysis_service` registered as daemon service `:tick_smc_ai`,
`edge_detector`, `gate`, `snapshot_store` — a per-tick SMC+AI fusion layer
separate from the 5-min scanner).

## 13. Full service directory map (all subpackages under `app/services/`)

```
adapters/option_chain          agents/                        ai/ (+autonomous, trading_bot, trading_agent)
algo_config/                   avrz/                          backtest/
candles/                       capital/                       concerns/
core/ (event_bus)               dhan/                          entries/ (+guards)
event_store/                   indicators/                    ledger/
live/                          market/                        market_context/
market_data/                   notifications/ (+telegram)      option_intelligence/ (empty dir)
optimization/                  options/ (+index_rules, strike_qualification)
options_buying/ (+strategies)  orders/ (+commands)             policies/
portfolio/                     position_manager/ (empty dir)   positions/ (+states, trailing_config)
redis_ui/                      research/                       risk/ (+rules)
signal/                        signals/                       smc/ (+confluence, detectors, tick_ai)
strategies/                    strike_selection/ (empty dir)   telegram/
trading/                       validators/                    volume/ (empty dir)
liquidity/ (empty dir)         auto_exp/ (LLM-planned experiment runner)
```
`option_intelligence`, `position_manager`, `strike_selection`, `volume`,
`liquidity` are empty directories — reserved names with no current
implementation, not active subsystems.

## 14. Stable vs Alpha layers (change policy — from `CLAUDE.md`)

**LOCKED (infra — touch only for a Critical Scenario: DhanHQ API break,
verified execution defect, state divergence, structural perf failure, or
security issue):**
DhanHQ gateways/adapters, WebSocket/market-data/caching (`market_feed_hub`,
`order_update_hub/handler`, `redis_tick_cache`, `tick_query`, `market_cache`,
`pnl_updater_service`, `redis_pnl_cache`), position lifecycle
(`active_cache`, `serializer`, `positions/states/*`), order execution
plumbing (`orders/commands/*`, `executor`, `entry_manager`, `exit_engine`,
`trailing_engine`, `mfe_exit_engine`, `gamma_trailing_engine`,
`expiry_rule_engine`, `unified_exit_checker`), risk-manager plumbing,
process wiring (`lib/trading_system/`, jobs, controllers/routes),
instrument/chain plumbing (`instrument.rb`, `chain_analyzer.rb`,
`derivative_chain_analyzer.rb`, `strike_selector.rb`, `strike_aggregator.rb`,
`expiry_calendar.rb`).

**ALPHA (safe to iterate freely):**
`signal/*`, `indicators/*`, `market_state/*`, `smc/*`,
`trading/trend_scorer.rb`, `trading/permission_resolver.rb`,
`entries/entry_guard.rb` + `entry_filter_engine.rb` +
`entry_guard_pipeline.rb` + all `entries/guards/*`,
`orders/analyzer.rb`/`adjuster.rb`/`adaptive_trailing.rb`/`gamma_detector.rb`,
`trading/trailing_engine.rb`, all `risk/*`, all `policies/*`,
`capital/allocator.rb`, `options/flow_analyzer.rb`,
`options/strike_qualification/*`, `options/historical_calibration_engine.rb`.

## 15. Config

`AlgoConfig.fetch` merge order (30s in-process cache):
1. `config/algo.yml` (base)
2. DB `settings` table → `algo_config_overrides` JSON (deep-merged)
3. `config/signal_tier_presets.yml` for tier `exploratory`|`standard`|`selective` (`SIGNAL_TIER` env or `signals.signal_tier`)
4. `LIVE_TRADING` env — unset/false forces `paper_trading.enabled: true`; `true` forces it `false` (gateway selection happens once at boot; restart to change)

**All percentages are DECIMAL** (`0.12` = 12%, never `12`).

Key `algo.yml` sections actually present: `paper_trading`, `ledger`,
`realtime` (tick-first execution controls), `trading_time_restrictions`,
`midday_guard`, `strategy_platform`, `options_buying` (large — see §6),
`expiry_week_power_trend`, `loss_streak_guard`, `segment_expectancy_guard`,
`trading.segment_expectancy`, `strike_cooldown_guard` (currently disabled),
`capital_allocator.post_peak_size_cut`, `sizing`, `feature_flags` (e.g.
`enable_trend_scorer: false` — legacy Supertrend+ADX path is still the
active default, TrendScorer is opt-in), `dhanhq`, `market.vix_gate`,
`indices` (per-index: `capital_alloc_pct`, `max_same_side`, `cooldown_sec`,
`max_concurrent_per_index`, `premium_band`, `otm_rules`, `risk_model`,
`trade_limits`, `adx_thresholds`, `strategies` sub-config for
open_interest/momentum_buying/btst/swing_buying), `trade_limits` (global
caps: 12 trades/day, 6 concurrent), `broker_fees` (₹20/order, ₹40/round
trip), `risk` (`max_exposure_rupees` per index, legacy `sl_pct`/`tp_pct`
fallback — actual SL/TP resolved by DTE via `risk.dte_parameters.by_dte`,
`iv_vol_gate`, `volume_velocity_gate`, `chain_confirmation_gate`).

Current live index parameters (from `algo.yml`, may drift — re-check before
quoting to the user as current):

| Index | capital_alloc_pct | premium_band | base_risk_pct | max_trades/day |
|---|---|---|---|---|
| NIFTY | 0.30 | 30–160 | 0.01 | 5 |
| BANKNIFTY | 0.30 | 60–650 | 0.02 | 10 |
| SENSEX | 0.30 | 40–320 | 0.02 | 4 |

Identity/lot/segment/execution defaults per index live in
`config/india_index_registry.yml`, not `algo.yml`.

## 16. Database (from `db/schema.rb`)

Core trading: `instruments`, `derivatives`, `position_trackers`,
`position_meta_snapshots`, `candles`, `trading_signals`, `trading_strategies`,
`trade_telemetry`, `trade_analytics`, `watchlist_items`, `market_holidays`,
`dhan_access_tokens`, `public_ip_logs`.

Strategy platform: `strategies`, `strategy_versions`, `strategy_runs`,
`strategy_signals`, `platform_variables`.

Paper trading (dual system — legacy + ledger, see §9): `paper_wallets`,
`paper_positions`, `paper_orders`, `paper_trades`, `paper_fills_logs`,
`paper_daily_wallets`, `ledger_accounts`, `ledger_journal_entries`,
`ledger_postings`.

Options/IV: `iv_snapshots`, `options_buying_signal_events`,
`best_indicator_params`, `calibration_runs`.

Research (see §10): `research_signals`, `research_option_bars`,
`research_option_candidates`, `research_premium_lifecycles`,
`research_raw_fetches`, `research_hypotheses`, `research_events`,
`research_event_strikes`, `research_event_exits`, `research_edge_registry`,
`research_experiment_registry`, `research_feature_registry`,
`research_feature_importances`, `research_dataset_snapshots`,
`research_data_quality_audits`.

SMC/config/misc: `smc_events`, `settings`, `algo_config_change_logs`,
`alpha_signals`.

AI agent framework: `ruby_llm_agents_executions`,
`ruby_llm_agents_execution_details`, `ruby_llm_agents_overrides`.

Infra: `solid_queue_*` (9 tables), `woods_units`/`woods_edges`/`woods_embeddings`
(codebase-indexing gem for AI assistant context, dev-only).

## 17. API surface (`config/routes.rb`)

```
/api/health, /api/dashboard, /api/positions[, /:id, /:id/close]
/api/signals, /api/dhan_access_token
/api/holdings, /api/funds[, /add, /withdraw]
/api/reports[/pnl, /trades, /performance, /export, /pnl_by_strategy, /pnl_by_instrument]
/api/orders, /api/depth, /api/equity_curve
/api/backtests (POST), /api/replays (POST)
/api/logs, /api/alerts (full CRUD)
/api/scheduler/tasks[, /:id/execute]
/api/smc/decision   (legacy /smc/decision → 301)
/api/candles/:index_key
/api/option_chain/:index_key
/api/market/vix
/api/analysis/:index_key[, /historical, /risk_explorer, /ai_snapshot (POST), /optimize (POST)]
/api/settings[, /fast_entry_mode, /change_logs, /bulk (PATCH), /deep_merge (PATCH), /update_ip (POST)]
/api/calibration_runs (index/show + apply)
/api/alpha/{status,history,performance}
/api/ledger/{balance,journal,positions/:id}
/api/circuit_breaker (show/trip POST/reset DELETE)
/api/trading_strategies (CRUD + validate/deploy)
/api/drawdown_guard/reset (DELETE)
/api/strategies (Strategy Platform: index/show/create + deploy/start/stop/restart/versions/signals/logs/variables)
/api/variables (global platform variables)
/api/strategies/health/{pool,session,backtest}
/api/research/signals, /api/research/lifecycles[, /run (POST), /expectancy]
/cable (ActionCable), /agents (RubyLLM::Agents::Engine, dev or ENABLE_AGENTS_DASHBOARD=true)
/api-docs (RSwag UI, dev or ENABLE_SWAGGER_UI=true)
/redis_ui (development only)
```

## 18. Recurring jobs (`config/recurring.yml` — dev vs prod differ mainly in "every day" vs "every weekday"/"during market hours")

Pre-market: `pre_market_iv_baseline` (8:30), `instruments_import` (8:45),
`iv_snapshot` (8:45), `candles_daily_backfill` (8:50),
`options_buying_daily_metrics` (9:08), `market_vix_gate_open` (9:01),
`options_buying_chain_radar_open` (9:16), `portfolio_reset` (9:15),
`clear_carried_overnight` (9:15), `research_daily_lifecycle_{nifty,banknifty,sensex}` (9:00),
`ai_trading_signal_nifty_open` (9:20), `ai_trading_signal_banknifty_open` (9:22).

Intraday: `market_vix_gate_refresh` (15 min), `options_buying_chain_radar_refresh`
(30 min), `options_buying_candle_precompute` (every 1 min, self-gates on
market hours), `alpha_scanner` (5 min), `ai_trading_signal_{nifty,banknifty}_refresh`
(30 min), `ledger_reconciliation` (30 min), `dhan_auto_ip_sync` (30 min),
`public_ip_log` (15 min).

Post-close: `options_buying_eod_carry` (15:10), `entry_funnel_metrics` (15:30),
`ledger_daily_close` (15:35), `smc_scanner` (16:00),
`ai_technical_analysis_{nifty,sensex}` (16:00), `autonomous_optimization`
(16:30).

Weekly: `candles_retention` (Sunday 2am — 2yr retention prune),
`weekly_options_calibration` (production only, Sunday 6am),
`clear_solid_queue_finished_jobs` (production only, hourly).

Run `rails solid_queue:load_recurring` after editing this file.

## 19. Token management

`Dhan::TokenManager`, 3-tier fallback (configured in
`config/initializers/dhanhq_config.rb`):
1. Authority server HTTP GET (`$TRADER_API_BASE_URL/auth/dhan/token`, 60s cache)
2. TOTP auto-refresh (`DHAN_PIN` + `DHAN_TOTP_SECRET`, `rotp` gem)
3. Static `ENV['DHAN_ACCESS_TOKEN']` fallback

Refresh restarts `Live::MarketFeedHub` to reconnect with the new token.
`Dhan::AutoIpUpdaterJob` (every 30 min) auto-syncs local public IP with
Dhan's IP whitelist when cooldown expires.

## 20. Environment variables

| Var | Required | Purpose |
|---|---|---|
| `DHAN_CLIENT_ID` | Yes | Broker client ID |
| `DHAN_ACCESS_TOKEN` | Yes | Static token fallback |
| `DHAN_PIN`, `DHAN_TOTP_SECRET` | Recommended | TOTP auto-refresh |
| `ENABLE_TRADING_SERVICES` | Auto (Procfile) | Gates daemon start |
| `PLACE_ORDER` | Live only | Must be `true` for real broker order submission |
| `LIVE_TRADING` | Recommended explicit | Forces effective paper/live at boot |
| `SIGNAL_TIER` | Optional | `exploratory`/`standard`/`selective` |
| `REDIS_URL`, `DATABASE_URL`, `RAILS_ENV` | Optional | Standard |
| `OLLAMA_MODEL`, `OLLAMA_BASE_URL`/`OLLAMA_HOST_URL`, `OLLAMA_TIMEOUT` | Optional | Local LLM |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Optional | Notifications |
| `ENABLE_AGENTS_DASHBOARD`, `ENABLE_SWAGGER_UI` | Optional | Prod-only mount gates |

## 21. Critical invariants (do not violate when reasoning about changes)

- DhanHQ only — no other broker integration exists or should be added.
- `event_bus.rb` has only a debug subscriber; live services talk via direct
  method calls, not pub/sub — despite `Strategies::Manager` *also* using
  `Core::EventBus` for `:candle_closed`/`:strategy_status_change`/
  `:strategy_signal`/`:strategy_error` — that usage is real, not debug-only,
  so the "EventBus is inert" claim in `CLAUDE.md`/README is only true for the
  original risk/PnL path, not for the newer strategy platform.
- `exit_engine.rb` is the single source of truth for exit placement.
- `TickQuery` returns `nil` (not zero) on cache miss.
- Position sizing must go through `capital/`.
- Solid Queue only, never Sidekiq/`ApplicationWorker`.
- Redis tick cache is write-through; must degrade gracefully if Redis is down.
- Never write to DB from inside a WebSocket tick handler.
- `Live::Gateway` is deprecated — use `Orders::GatewayLive` directly.
- Gateway (paper/live) is chosen once at boot — changing `LIVE_TRADING`
  requires a daemon restart to take effect.

## 22. Known documentation debt (tell the research AI this explicitly)

- `README.md` and `docs/architecture/system_overview.md` both describe an
  11-service supervisor with `Signal::Scheduler` as the live signal loop.
  The actual registry (`lib/trading_system/bootstrap.rb`) has ~19 entries
  and does not register `Signal::Scheduler` at all — it registers
  `Strategies::Manager` instead. Treat any cadence/service-count claim in
  prose docs as suspect until confirmed against `bootstrap.rb`.
- The entry guard count is documented as 20 in multiple places; the actual
  directory has 33 guard files. Confirm order/count from
  `entry_guard_pipeline.rb` directly.
- `docs/` contains ~150 files, many under `docs/archive/` (explicitly
  superseded) — when researching a topic, prefer `docs/architecture/`,
  `docs/trading/`, `docs/services/`, and `docs/infra-strategy-setup/` over
  `docs/archive/`, but verify against source for anything load-bearing.
- Four AI decision surfaces coexist (`ai/trading_bot`, `ai/trading_agent`,
  `ai/autonomous`, `agents/trading_orchestrator`) with no doc reconciling
  which is authoritative — ask the user before assuming one is "the" AI path.
