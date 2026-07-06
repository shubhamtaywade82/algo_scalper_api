# 00 — Overview

## Vision

Transform `algo_scalper_api` from a trading **application** (one hardcoded Supertrend options-buying
pipeline) into a trading **platform**: a personal, single-user trading operating system where the
platform owns all infrastructure and strategies are lightweight, versioned, hot-swappable plugins.

> **Key principle** (from the E2E flow diagram): *The platform owns Data, Indicators, Risk,
> Execution, and State. Strategies are pure decision engines that plug into the platform.*

A strategy answers exactly one question — *given everything I know, should I BUY CE / BUY PE /
EXIT / HOLD / MOVE SL?* — and nothing else. It never touches WebSockets, Redis, DhanHQ, order
placement, position sizing, or risk checks.

## Platform vs strategy responsibility split

| Platform owns (shared, stable) | Strategy owns (per-plugin, iterated) |
| --- | --- |
| Market data ingestion (WebSocket, REST backfill) | Entry logic |
| Candle building + persistence (1m base, derived TFs) | Exit intent |
| Indicator computation (one calculation, many consumers) | Signal confidence + reason |
| Market structure / SMC / liquidity engines | Parameter defaults (via manifest) |
| Option chain fetch + strike qualification | |
| Risk engine, daily limits, circuit breaker | |
| Position sizing (`Capital::Allocator`) | |
| Order execution (gateways, placer, idempotency) | |
| Position lifecycle, PnL, trailing, exits | |
| Scheduling, logging, replay, notifications | |
| Config, variables, secrets | |

The strategy cannot bypass risk: it emits a signal object; the platform's guard pipeline
(`Entries::EntryGuard`, unchanged) remains the sole gate to execution.

## Layer map (keyed to the E2E flow diagram)

| # | Diagram layer | Current status | Detail |
| --- | --- | --- | --- |
| 1 | Data Ingestion (historical loader, WS manager, tick processor, OHLCV DB) | `PARTIAL` | WS + tick processing + backfill EXIST; **OHLCV DB missing** → [03](03_data_layer.md) |
| 2 | Market Data Processing (candle builder, multi-TF aggregator, indicator engine, structure engine, liquidity engine) | `PARTIAL` | Redis 1m builder + rich indicators + SMC engines EXIST; durable multi-TF derivation missing → [03](03_data_layer.md) |
| 3 | Market Intelligence (option chain engine, Greeks engine, strike selector, event bus) | `PARTIAL` | Chain analytics + strike qualification + in-process bus EXIST; **Greeks computation deliberately skipped** → [10](10_greeks_and_indicator_streaming.md) |
| 4 | Strategy Runtime (plugins, StrategyContext, StrategyManager) | `DEAD`/`NEW` | Scaffold exists with no callers; the core of this upgrade → [04](04_strategy_plugin_system.md), [05](05_runtime_manager.md) |
| 5 | Decision & Risk (signal aggregator, risk engine, position manager, quantity engine, trade plan) | `EXISTS` | 10-guard entry pipeline, risk manager, allocator — reused as-is (LOCKED) |
| 6 | Execution (option selector, order manager, DhanHQ API, order-update listener) | `EXISTS` | Gateways, placer, order update hub — reused as-is (LOCKED) |
| 7 | Post-Trade & Exit (monitoring, exit conditions, square-off, notify/log) | `EXISTS` | ExitEngine, trailing, unified exit checker — reused as-is (LOCKED) |
| — | Platform Services (scheduler, replay, logging, metrics, alerts, config/secrets) | `PARTIAL` | Config mature; backtest engines exist without APIs; live log streaming + strategy variables missing → [06](06_platform_services.md) |

## Non-goals (explicitly out of scope)

- **Multi-tenancy** — one user, one Dhan account, many strategies. No orgs/roles/invitations.
- **Billing / credits** — Dhan Cloud's metering has no value locally.
- **Container-per-strategy** — strategies run as threads inside the existing trading daemon.
  Docker isolation is a documented future option, not part of this plan (see D-00.1).
- **Public API design** — endpoints serve the local dashboard only; existing auth pattern applies.
- **Python/Node strategy runtimes** — Ruby-only for v1. Multi-runtime is a future extension the
  plugin contract does not preclude.

## Foundational decisions

- **D-00.1** — Single process, thread-per-strategy. No per-strategy containers. The
  `Strategies::Manager` runs inside the existing trading daemon (`lib/trading_system/daemon.rb`),
  registered with the existing supervisor. Revisit only if strategy count or fault isolation
  demands it; the plugin contract is container-agnostic so migration stays possible.
- **D-00.2** — **Strategy code lives in files on disk** (`strategies/` workspace, git-tracked).
  The database stores metadata + file path + SHA-256 checksum only. **Code is never stored in or
  evaluated from the database.** This is a safety invariant (restated in 04, 06, 09).
- **D-00.3** — This suite supersedes `implementation_plan.md` (the ChatGPT transcript) and
  `docs/NEW_ANALYTICS_AND_STRATEGY_LAYER.md`. Conflicts resolve in favor of this suite.
- **D-00.4** — LOCKED execution infrastructure (per `CLAUDE.md` change policy) is consumed as-is.
  The upgrade plugs in *above* `Entries::EntryGuard`. The single LOCKED edit is the Phase-4
  supervisor lifecycle addition, handled as an explicit carve-out → [09](09_risks_and_change_policy.md).

## Glossary

| Term | Meaning |
| --- | --- |
| **Strategy plugin** | A Ruby class in `strategies/<slug>/strategy.rb` subclassing `Strategies::Base`, implementing `#call(context)` |
| **StrategyContext** | Read-only facade handed to a plugin per invocation: candles, indicators, structure, chain, position, risk state, clock, params |
| **Signal object** | Immutable value object a plugin returns: `Signals::BuyCall`, `Signals::BuyPut`, `Signals::Exit`, `Signals::Hold` |
| **Registry** | DB tables (`strategies`, `strategy_versions`, `strategy_runs`, `strategy_signals`) tracking metadata, versions, lifecycle |
| **Workspace** | The `strategies/` directory tree holding plugin code and manifests |
| **Deploy pipeline** | validate → scan → snapshot version → register → (re)load |
| **Runtime manager** | `Strategies::Manager` — starts/stops/restarts/monitors strategy threads |
| **Replay parity** | Gate requiring an extracted plugin to emit identical signals to the legacy path over recorded sessions |
| **LOCKED layer** | Execution infra frozen by `CLAUDE.md` change policy; modified only under named carve-outs |
