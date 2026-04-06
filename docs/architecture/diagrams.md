# System Architecture Diagrams

This document points to the **canonical diagram set** and keeps a few legacy diagrams for quick reference.

## Canonical diagrams (C4, flows, architecture)

**Full set:** [diagrams/complete-system-diagrams.md](diagrams/complete-system-diagrams.md)

- **C4 Level 1** — System context (Trader, DhanHQ, Telegram, optional Authority/Ollama)
- **C4 Level 2** — Containers (Web, Trading Daemon, Jobs, Dashboard, PostgreSQL, Redis)
- **C4 Level 3** — Components (Supervisor + 11 services, Web API + ActionCable)
- **High-level process model** — ASCII view of `bin/dev` (4 processes)
- **End-to-end flow** — Signal → Entry (10 guards) → Order → Position → Exit (per-tick + 5s)
- **Data flow** — Ticks → PnL pipeline → RedisPnlCache → RiskManager → ExitEngine
- **Entry guard pipeline** — Order of 10 guards
- **Exit decision flow** — UnifiedExitChecker + run_enforcement_cycle

**Index:** [diagrams/README.md](diagrams/README.md)

**Trading modes (run profiles, paper/live, env flags):**
[../diagrams/trading-modes.md](../diagrams/trading-modes.md)

---

## Quick reference (legacy)

### 1. High-Level Logic Flow
Visualizing the 10,000ft view of the system from Data to Execution.


```mermaid
graph TD
    subgraph Market_Data
        A[DhanHQ WebSocket] --> B[MarketFeedHub]
        B --> C[TickCache & Redis]
    end

    subgraph Analysis
        D[Signal::Scheduler] --> E[Signal::Engine]
        C --> E
        F[SMC::Scanner] --> E
        E --> G[Comprehensive Validation]
    end

    subgraph Execution
        G --> H[Orders::EntryManager]
        H --> I[OrderRouter]
        I --> J[Broker/Paper API]
    end

    subgraph Monitoring
        J --> K[PositionTracker DB]
        B --> L[RiskManagerService]
        L --> M[UnifiedExitChecker]
        M --> N[ExitEngine]
        N --> I
    end
```

## 2. Signal Generation Pipeline
The internal logic of `Signal::Engine`.

```mermaid
stateDiagram-v2
    [*] --> CheckMarketOpen
    CheckMarketOpen --> GetStrategies: Open
    CheckMarketOpen --> [*]: Closed

    state GetStrategies {
        [*] --> StrategyLookup
        StrategyLookup --> StandardMode: Supertrend/ADX
        StrategyLookup --> AdvancedMode: StrategyRecommender
    }

    GetStrategies --> PrimaryAnalysis
    PrimaryAnalysis --> ConfirmationAnalysis
    ConfirmationAnalysis --> ComprehensiveValidation

    state ComprehensiveValidation {
        DirectionGate
        ADX_Strength
        SMC_Alignment
    }

    ComprehensiveValidation --> StrikeSelection: Pass
    ComprehensiveValidation --> [*]: Fall

    StrikeSelection --> EntryGuard
    EntryGuard --> [*]: Order Placed
```

## 3. Risk Management Hierarchy (Exit Priority)
The decision tree used by `UnifiedExitChecker`.

```mermaid
graph TD
    Start[Tick Received] --> ETF[Early Trend Failure?]
    ETF -- Yes --> Exit[Trigger Exit]
    ETF -- No --> SL[Stop Loss Hit?]
    SL -- Yes --> Exit
    SL -- No --> TP[Take Profit Hit?]
    TP -- Yes --> Exit
    TP -- No --> TR[Trailing Stop Triggered?]
    TR -- Yes --> Exit
    TR -- No --> TM[Time Stop reached?]
    TM -- Yes --> Exit
    TM -- No --> Wait[Hold Position]
```
