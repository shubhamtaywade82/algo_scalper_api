# Complete System Diagrams

Diagrams derived from the current Algo Scalper API codebase: C4 (Level 1–3), high-level architecture, and end-to-end/data flows. Implementation references: `lib/trading_system/bootstrap.rb`, `Procfile.dev`, `app/services/entries/entry_guard_pipeline.rb`, `app/services/live/unified_exit_checker.rb`, `app/services/live/risk_manager_service/runner.rb`.

---

## 1. C4 Level 1 — System Context

Who uses the system and which external systems it talks to.

```mermaid
flowchart LR
    subgraph Users
        Trader([Trader / Operator])
    end

    subgraph AlgoScalper["Algo Scalper API"]
        API[API + Trading Daemon]
    end

    subgraph External["External Systems"]
        DhanHQ[DhanHQ API<br/>Broker + Market Data]
        Telegram[Telegram<br/>Notifications]
        Authority[Authority Server<br/>Optional Token]
        Ollama[Ollama<br/>Optional local LLM]
    end

    Trader -->|"Configures, monitors, dashboard"| API
    API -->|"Orders, option chain, WebSocket ticks"| DhanHQ
    API -->|"Alerts, PnL, daily stats"| Telegram
    API -.->|"Token (if configured)"| Authority
    API -.->|"AI technical analysis"| Ollama
```

**Elements:**
- **Trader:** Configures `algo.yml`, views dashboard, uses `/api/circuit_breaker`, health, settings.
- **DhanHQ:** Orders (REST), option chain, WebSocket market feed + order updates.
- **Telegram:** Trade alerts, PnL milestones, daily stats, SMC signals.
- **Authority server:** Optional; provides Dhan access token (`TRADER_API_BASE_URL/auth/dhan/token`).
- **Ollama:** Optional local LLM (`ollama-client`); used by `AiTechnicalAnalysisJob` and related AI paths for NIFTY/SENSEX.

---

## 2. C4 Level 2 — Containers

Deployable runnables and shared data stores. Aligned with `Procfile.dev` and deployment (web + trading + jobs + dashboard).

```mermaid
flowchart TB
    subgraph Host["Single host (e.g. bin/dev)"]
        subgraph Processes["OS processes"]
            Web["Web<br/>Rails API :3001"]
            Daemon["Trading Daemon<br/>11 services in threads"]
            Jobs["Jobs<br/>Solid Queue worker"]
            Dashboard["Dashboard<br/>Next.js"]
        end

        subgraph DataStores["Shared data stores"]
            PG[(PostgreSQL)]
            Redis[(Redis)]
        end
    end

    subgraph External["External"]
        DhanHQ[DhanHQ API]
        Telegram[Telegram]
    end

    Web --> PG
    Web --> Redis
    Daemon --> PG
    Daemon --> Redis
    Jobs --> PG
    Jobs --> Redis
    Dashboard -->|"HTTP to Web"| Web
    Daemon -->|"WebSocket + REST"| DhanHQ
    Web -.->|"Optional"| Telegram
    Daemon -.->|"Optional"| Telegram
```

**Containers:**
- **Web:** Rails API (Puma), ActionCable, health, dashboard API, circuit breaker, settings. Does **not** run trading services.
- **Trading Daemon:** Single process; `TradingSystem::Supervisor` runs 11 services in threads. Market feed, signal scheduler, risk manager, exit engine, reconciliation, etc.
- **Jobs:** Solid Queue worker; `InstrumentsImportJob`, `SmcScannerJob`, `AiTechnicalAnalysisJob`.
- **Dashboard:** Next.js frontend; consumes Web API.
- **PostgreSQL:** Durable state (instruments, derivatives, position_trackers, candles, settings, etc.).
- **Redis:** Tick cache, PnL cache, circuit breaker, position state, rate limits.

---

## 3. C4 Level 3 — Components

### 3a. Trading Daemon (components)

Services registered in `lib/trading_system/bootstrap.rb` and started by `TradingSystem::Supervisor`.

```mermaid
flowchart TB
    subgraph Supervisor["TradingSystem::Supervisor"]
        direction TB
        S[supervisor.start_all]
    end

    subgraph Services["11 services (threads / on-demand)"]
        MF[MarketFeedHubService]
        SS[Signal::Scheduler]
        RM[RiskManagerService]
        PH[PositionHeartbeat]
        OR[OrderRouter]
        PP[PaperPnlRefresher]
        EE[ExitEngine]
        AC[ActiveCacheService]
        REC[ReconciliationService]
        SN[StatsNotifierService]
        SM[Smc::Scanner]
    end

    S --> MF
    S --> SS
    S --> RM
    S --> PH
    S --> OR
    S --> PP
    S --> EE
    S --> AC
    S --> REC
    S --> SN
    S --> SM

    MF -->|"ticks"| TC[TickCache / Redis]
    SS -->|"30s"| SE[Signal::Engine]
    SE -->|"entry"| EG[EntryGuard]
    EG -->|"order"| OR
    RM -->|"5s + per-tick"| UEC[UnifiedExitChecker]
    UEC -->|"exit"| EE
    EE --> OR
    REC -->|"30s"| DB[(PostgreSQL)]
```

| # | Key | Component | Cadence |
|---|-----|-----------|---------|
| 1 | :market_feed | Live::MarketFeedHubService | WebSocket event-driven |
| 2 | :signal_scheduler | Signal::Scheduler | 30s |
| 3 | :risk_manager | Live::RiskManagerService | 5s loop + per-tick EventBus |
| 4 | :position_heartbeat | TradingSystem::PositionHeartbeat | 10s |
| 5 | :order_router | TradingSystem::OrderRouter | On-demand |
| 6 | :paper_pnl_refresher | Live::PaperPnlRefresher | 1s (paper) |
| 7 | :exit_manager | Live::ExitEngine | On-demand |
| 8 | :active_cache | Positions::ActiveCacheService | On-demand |
| 9 | :reconciliation | Live::ReconciliationService | 30s |
| 10 | :stats_notifier | Live::StatsNotifierService | At market close |
| 11 | :smc_scanner | Smc::Scanner | 5 min |

### 3b. Web process (components)

```mermaid
flowchart LR
    subgraph Web["Web process"]
        API[Rails API<br/>Controllers]
        Cable[ActionCable<br/>Solid Cable]
        Rack[Rack / Puma]
    end

    API --> Health["/api/health"]
    API --> Dashboard["/api/dashboard"]
    API --> Positions["/api/positions"]
    API --> CircuitBreaker["/api/circuit_breaker"]
    API --> Settings["/api/settings"]
    Cable --> PositionsChannel[PositionsChannel]
    Cable --> DashboardChannel[DashboardChannel]
```

---

## 4. C4 Level 4 — Code (sample)

One code-level view: entry guard pipeline and its guard classes. Implementation: `app/services/entries/entry_guard_pipeline.rb`, `app/services/entries/guards/*.rb`.

```mermaid
flowchart TB
    subgraph Pipeline ["EntryGuardPipeline"]
        run["run(context)"]
        h1["handlers.each"]
        run --> h1
    end

    subgraph Guards ["Guards in order"]
        H1[CircuitBreakerGuard]
        H2[BosContractGuard]
        H3[TimeRegimeGuard]
        H4[BankniftyLastWeekGuard]
        H5[EdgeFailureGuard]
        H6[DailyLimitsGuard]
        H7[InstrumentLookupGuard]
        H8[ExposureGuard]
        H9[CooldownGuard]
        H10[LtpResolutionGuard]
    end

    Post[EntryGuard post-pipeline]
    Return[return blocked]

    h1 --> H1
    H1 --> H2
    H2 --> H3
    H3 --> H4
    H4 --> H5
    H5 --> H6
    H6 --> H7
    H7 --> H8
    H8 --> H9
    H9 --> H10
    H10 -->|pass| Post

    H1 --> Return
    H2 --> Return
    H3 --> Return
    H4 --> Return
    H5 --> Return
    H6 --> Return
    H7 --> Return
    H8 --> Return
    H9 --> Return
    H10 --> Return
```

**Key classes:**
- `Entries::EntryGuardPipeline` — holds default_handlers array, invokes each guard with context.
- `Entries::Guards::*Guard` — each implements `.call(context)` → `PASS` or `{ blocked: reason }`.
- `Entries::EntryGuard` — builds context, calls `entry_guard_pipeline.run(context)`, then post-pipeline checks and `place_market`.

---

## 5. High-Level Process Model

What `./bin/dev` (Procfile.dev) starts. Web and Trading are separate OS processes; they share PostgreSQL and Redis only.

```
┌─────────────────────────────────────────────────────────────────────────┐
│ bin/dev (foreman)                                                       │
├────────────────┬────────────────┬────────────────┬─────────────────────┤
│ web             │ trading        │ jobs           │ dashboard           │
│ bin/rails       │ ENABLE_...=true│ bin/jobs       │ cd dashboard        │
│ server -p 3001  │ rake           │                │ npm run dev         │
│                 │ trading:daemon │                │                     │
├─────────────────┼────────────────┼────────────────┼─────────────────────┤
│ Rails API       │ Supervisor     │ Solid Queue    │ Next.js             │
│ ActionCable     │ 11 services    │ recurring      │ frontend            │
│ port 3001      │ in threads     │ tasks          │                     │
└────────┬────────┴───────┬────────┴───────┬────────┴─────────────────────┘
         │                │                │
         └────────────────┼────────────────┘
                           │
                    ┌──────┴──────┐
                    │ PostgreSQL  │
                    │ Redis       │
                    └─────────────┘
```

---

## 6. End-to-End Flow: Signal to Exit

Single trade lifecycle from signal generation to exit order.

```mermaid
flowchart TB
    subgraph Trigger["Trigger (every 30s)"]
        A[Signal::Scheduler] --> B[IndexConfigLoader.load_indices]
        B --> C[Signal::Engine.run_for per index]
    end

    subgraph Signal["Signal generation"]
        C --> D[Supertrend/ADX + validation]
        D --> E[EntryFilterEngine]
        E --> F[PermissionResolver / SMC]
        F --> G[ExpiryModel / ChainAnalyzer]
        G --> H[Strike picks + entry_metadata]
    end

    subgraph Entry["Entry path"]
        H --> I[EntryGuard.try_enter]
        I --> J[EntryGuardPipeline: 10 guards]
        J --> K[Post-pipeline: sizing, weekly, BOS]
        K --> L[Orders.config.gateway.place_market]
        L --> M[PositionTracker.create]
        M --> N[Subscribe to WebSocket]
    end

    subgraph Monitor["Position monitoring"]
        N --> O[DhanHQ ticks → MarketFeedHub]
        O --> P[TickCache + Redis]
        P --> Q[PnlUpdaterService 250ms flush]
        Q --> R[RedisPnlCache + EventBus :ltp]
        R --> S[RiskManagerService]
    end

    subgraph Exit["Exit path"]
        S --> T[UnifiedExitChecker per-tick]
        S --> U[run_enforcement_cycle 5s]
        T --> V[ExitEngine.execute_exit]
        U --> V
        V --> W[OrderRouter.exit_market]
        W --> X[Gateway Paper/Live]
        X --> Y[PositionTracker mark_exited]
    end

    Trigger --> Signal
    Signal --> Entry
    Entry --> Monitor
    Monitor --> Exit
```

---

## 7. Data Flow: Ticks and PnL

How market ticks become PnL and drive exit decisions.

```mermaid
flowchart TD
    subgraph Ingress["Ingress"]
        WS[DhanHQ WebSocket]
    end

    subgraph Feed["Feed layer"]
        MF[MarketFeedHub.handle_tick]
        TC[TickCache.put]
        RTC[RedisTickCache]
        PI[PositionIndex.trackers_for]
    end

    subgraph PnL["PnL pipeline"]
        PU[PnlUpdaterService.cache_intermediate_pnl]
        Flush["Every 250ms flush"]
        Batch[Batch DB load, compute PnL]
        RPC[RedisPnlCache.store_pnl]
        EB[EventBus.publish :ltp]
    end

    subgraph Consumers["Consumers"]
        RM[RiskManagerService.handle_pnl_event]
        UEC[UnifiedExitChecker.check_exit_conditions]
        EE[ExitEngine.execute_exit]
        Broadcast[ActionCable positions channel]
    end

    WS --> MF
    MF --> TC
    MF --> RTC
    MF --> PI
    PI --> PU
    PU --> Flush
    Flush --> Batch
    Batch --> RPC
    RPC --> EB
    EB --> RM
    RM --> UEC
    UEC --> EE
    RPC --> Broadcast
```

---

## 8. Entry Guard Pipeline (component-level)

Order of the 10 guards; first block wins.

```mermaid
flowchart LR
    A[Context] --> G1[1. CircuitBreaker]
    G1 --> G2[2. BosContract]
    G2 --> G3[3. TimeRegime]
    G3 --> G4[4. BankniftyLastWeek]
    G4 --> G5[5. EdgeFailure]
    G5 --> G6[6. DailyLimits]
    G6 --> G7[7. InstrumentLookup]
    G7 --> G8[8. Exposure]
    G8 --> G9[9. Cooldown]
    G9 --> G10[10. LtpResolution]
    G10 --> Pass[PASS → post-pipeline]
```

---

## 9. Exit Decision Flow (high-level)

Two paths: per-tick (UnifiedExitChecker) and 5s enforcement cycle.

```mermaid
flowchart TB
    subgraph PerTick["Per-tick (EventBus :ltp)"]
        A[RedisPnlCache snapshot] --> B[Early trend failure?]
        B --> C[Stop loss?]
        C --> D[Take profit?]
        D --> E[Trailing stop?]
        E --> F[Time-based exit?]
        F --> G[ExitEngine.execute_exit]
    end

    subgraph FiveSec["5-second loop"]
        H[advance_trade_state] --> I[Premium R-stop]
        I --> J[TrailingEngine]
        J --> K[Profit floor]
        K --> L[Structure invalidation]
        L --> M[Premium momentum failure]
        M --> N[R:R profit booking]
        N --> O[Percentage PnL exit]
        O --> P[Time stop]
        P --> Q[Time-based exit]
        Q --> G
    end

    G --> R[OrderRouter → Gateway]
```

---

## References

- **Bootstrap:** `lib/trading_system/bootstrap.rb`
- **Processes:** `Procfile.dev`
- **Entry guards:** `app/services/entries/entry_guard_pipeline.rb`
- **Exit (per-tick):** `app/services/live/unified_exit_checker.rb`
- **Exit (5s):** `app/services/live/risk_manager_service/runner.rb`, `exit_enforcement.rb`
- **Trade lifecycle:** `docs/architecture/execution-flow.md`
- **Entry/exit rules:** `docs/trading/entry_and_exit_rules.md`
