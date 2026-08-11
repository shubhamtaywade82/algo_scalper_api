# Algo Scalper Platform v2.0 — Codebase Audit & Architectural Reconciliation Report

> **Document Type**: Codebase Review, Discrepancy Audit, and Reconciled System Architecture  
> **Original Reference**: [`docs/AlgoScalperPlatform-v2.0.md`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/docs/AlgoScalperPlatform-v2.0.md)  
> **Target System**: `algo_scalper_api` (Ruby 3.3.4, Rails 8.1.3 API, Solid Queue, Redis, Next.js, Node.js Sidecar with `dhanhq-ts`, DhanHQ v2)  
> **Date**: August 7, 2026  

---

## 1. Executive Summary

This document provides a comprehensive review and audit comparing the specification in [`docs/AlgoScalperPlatform-v2.0.md`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/docs/AlgoScalperPlatform-v2.0.md) against the actual implementation of the **`algo_scalper_api`** repository.

### Key Finding regarding Node.js & `dhanhq-ts`
The Node.js TypeScript engine using `@shubhamtaywade82/dhanhq-ts` **IS PRESENT** in the codebase under [`node-sidecar/`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/). 

However, its architectural role differs from the original template in `v2.0.md`:
* **Original `v2.0.md` Spec**: Envisioned Node.js as the monolithic primary hot-path engine replacing Rails for tick ingestion, candle building, and simple EMA strategy evaluation.
* **Actual Production Architecture**: 
  - **Ruby Trading Daemon (`TradingSystem::Supervisor`)**: Acts as the primary trading supervisor, tick feed hub (`Live::MarketFeedHub`), and quantitative signal engine (SMC + AVRZ + Ollama AI).
  - **Node.js TypeScript Sidecar ([`node-sidecar/`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/))**: Uses `@shubhamtaywade82/dhanhq-ts` (v0.4.1) as an **Auxiliary Execution & Defined-Risk Strategy Skill Resolver** connected via Redis channels (`dhan:execution:intents`, `dhan:execution:fills`, `dhan:execution:exits`). It is managed automatically alongside Rails processes in [`Procfile.dev`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/Procfile.dev#L5). It no longer opens a Dhan WebSocket of its own — that collided with Rails' own `Live::MarketFeedHub`/`Live::OrderUpdateHub` WS clients (429 handshake errors) — so its Greeks-analytics module and tick-driven exit path have been removed/are dormant; see `node-sidecar/` source comments for the current state.

---

## 2. Comparative Architecture Matrix

| Component / Layer | Original `v2.0.md` Spec | Actual `algo_scalper_api` Implementation | Status & Reconciled Design |
| :--- | :--- | :--- | :--- |
| **Control Plane API** | Rails API | Rails 8.1.3 API-only (`app/controllers/api/`) | **Match** — Rails API provides authentication, control endpoints, and DB state |
| **Node.js Engine & `dhanhq-ts`** | Monolithic hot-path engine in `apps/engine/` | [`node-sidecar/`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/) running `@shubhamtaywade82/dhanhq-ts` (v0.4.1) | **Present as Sidecar**: Auxiliary execution engine, pre-trade risk pipeline, strategy skill resolver (Greeks-analytics module removed, no WS of its own) |
| **Primary Trading Daemon** | Not specified (assumed pure Rails API) | Multi-threaded Ruby Trading Daemon (`lib/trading_system/`, `TradingSystem::Supervisor`) running 11 threads | **Present**: Manages live WebSocket feed (`Live::MarketFeedHub`), SMC/AVRZ signals, position indexing, and core risk monitoring |
| **Frontend UI** | SolidJS + Vite | Next.js (React) in [`dashboard/`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/dashboard/) + ActionCable WebSockets | **Reconciled**: Next.js React frontend dashboard |
| **Background Processing** | Sidekiq | Solid Queue (`app/jobs/`, `config/recurring.yml`) | **Reconciled**: Uses Rails 8 Solid Queue for recurring background jobs |
| **Trading Strategies** | Simple 5-min EMA 9/21 Breakout on NIFTY | **SMC** (FVG/BOS/CHoCH/OB) + **AVRZ** + **Option Greeks** + **MTF AI Agent** + **DhanHQ-TS Strategy Skills** | **Reconciled**: Multi-layer quantitative strategies + Node.js multi-leg strategy skill resolver |
| **Broker Integration** | `dhanhq-client` & `dhanhq-ts` | Dual integration: `DhanHQ::Client` (Ruby) + `@shubhamtaywade82/dhanhq-ts` (Node sidecar) | **Match**: Both Ruby and TypeScript DhanHQ clients are active |
| **Execution Gateways** | `PaperRouter` / `LiveDhanRouter` | `Orders::GatewayPaper` & `Orders::GatewayLive` (Ruby) + `PaperExecutionEngine` & `LiveExecutionEngine` (Node sidecar) | **Reconciled**: Dual execution gateways coordinated via Redis pub/sub |

---

## 3. Detailed Architecture of `node-sidecar/`

The Node.js sidecar lives in [`node-sidecar/`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/) and is driven by `@shubhamtaywade82/dhanhq-ts`.

### 3.1 Components & Modules

1. **Entry Point ([`node-sidecar/src/index.ts`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/src/index.ts))**:
   - Initialized via `ts-node src/index.ts`.
   - Protects against process crashes with `uncaughtException` and `unhandledRejection` guards so sidecar errors never terminate the main Rails daemon process group.

2. **Execution Engine ([`node-sidecar/src/executor.ts`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/src/executor.ts))**:
   - Subscribes to Redis channel `dhan:execution:intents`.
   - Instantiates `OrderTracker`, `PositionMonitor`, `Pipeline`, and `createSkillRegistry()` from `@shubhamtaywade82/dhanhq-ts`.
   - Executes pre-trade risk checks via `Pipeline` (`maxQuantity`, `dailyMaxLoss`).
   - Resolves defined-risk multi-leg options strategy skills (e.g. `bull_call_spread`, `iron_condor`).
   - Dispatches orders via [`PaperExecutionEngine`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/src/engines/paper.ts) or [`LiveExecutionEngine`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/node-sidecar/src/engines/live.ts).
   - Publishes order fill notifications to `dhan:execution:fills` and position exits to `dhan:execution:exits`.

3. **Greeks & Analytics Engine — removed**: `node-sidecar/src/analytics.ts` (real-time Greeks calc, cached in Redis under `dhan:market:greeks:{securityId}`) was deleted along with the sidecar's Dhan WebSocket — it depended on market-feed ticks the sidecar no longer receives, since that WS collided with Rails' own `Live::MarketFeedHub`/`Live::OrderUpdateHub` clients (429 handshake errors).

---

## 4. Multi-Process Runtime Pipeline (`Procfile.dev`)

The overall platform runs as 5 integrated processes managed by Foreman:

```text
1. web:       Rails 8.1 Puma API server (Port 3001)
2. trading:   Ruby Trading Daemon (TradingSystem::Supervisor managing 11 threads)
3. jobs:      Solid Queue Worker (Background & recurring scheduled tasks)
4. dashboard: Next.js Frontend Dashboard (npm run dev)
5. sidecar:   Node.js Execution Sidecar (node-sidecar / dhanhq-ts)
```

---

## 5. Quantitative KPI Framework

### 5.1 Trading Strategy KPIs
* **Net PnL**: Realized PnL + Unrealized PnL − Total Charges (Brokerage, STT, Exchange Fees, GST, Stamp Duty).
* **Win Rate Target**: $\ge 55\%$ across executed scalper trades.
* **Expectancy Target**: $> 0.5R$ per trade after slippage and costs.
* **Maximum Daily Drawdown (MDD)**: $\le 5\%$ daily equity limit (enforced by `Risk::CircuitBreaker` and `Pipeline`).

### 5.2 Execution & Sidecar KPIs
* **Sidecar Intent Processing Latency**: $< 20 \text{ ms}$ from Redis `dhan:execution:intents` reception to `dhanhq-ts` dispatch.
* **Duplicate Order Rate**: $0\%$ (guaranteed via SHA256 deterministic correlation IDs and `OrderTracker`).

---

## 6. Actionable Engineering Roadmap

### Item 1: Options Expiry Auto-Settlement Handler (High Priority)
* **Issue**: Expired option contracts (e.g. SENSEX PE expiring on Thursday/Friday) remain `active` because [`ClearCarriedOvernightPositionsJob`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/app/jobs/clear_carried_overnight_positions_job.rb) attempts to place market sell orders to DhanHQ at 9:15 AM next morning, which DhanHQ rejects.
* **Action**: Update `ClearCarriedOvernightPositionsJob` and `RiskManagerService` to detect `tracker.watchable&.expiry_date < Date.current`. Settle the position locally (`mark_exited!` at ₹0.00 / intrinsic value) without dispatching unfillable broker orders.

### Item 2: Same-Day Expiry Carry Guard
* **Issue**: [`OptionsBuying::EodCarryManager`](file:///home/nemesis/project/trading-workspace/bots/algo_scalper_api/app/services/options_buying/eod_carry_manager.rb) can tag positions for overnight carry.
* **Action**: Disallow overnight carry tagging if `expiry_date == Date.current`.

### Item 3: Node Sidecar Error Logging Hardening
* **Enhancement**: Enhance error reporting in `node-sidecar/src/executor.ts` around Redis intent message handling during token rotation. (The sidecar no longer opens its own Dhan WebSocket — see `node-sidecar/` source comments — so this should not involve reintroducing a WS order stream there.)
