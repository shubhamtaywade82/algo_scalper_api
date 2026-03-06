# C2: Container Architecture

Detailed look at the technical containers that make up the ARES system.

## Overview
ARES is built on a distributed boundary but typically runs as a single logical unit. It separates concern between the **Web Interface**, the **Trading Daemon**, and the **State Cache**.

```mermaid
C4Container
    title Container Diagram for ARES Trading System

    Container(web, "Web Dashboard", "Rails / Vue3", "Provides UI for monitoring and control.")
    Container(daemon, "Trading Daemon", "Ruby / BaseService", "Orchestrates signal generation and risk management.")
    Container(ws_hub, "Market Feed Hub", "WebSocket Client", "Ingests real-time tick data.")

    ContainerDb(postgres, "PostgreSQL", "Relational Database", "Stores historical trades, instruments, and config.")
    ContainerDb(redis, "Redis", "Key-Value Store", "Low-latency cache for live ticks, PnL, and circuit breaker status.")

    Rel(web, ares, "Interacts with", "HTTPS")
    Rel(daemon, postgres, "Reads/Writes", "PostgreSQL Wire")
    Rel(daemon, redis, "Reads/Writes", "Redis Protocol")
    Rel(daemon, ws_hub, "Subscribes to", "In-process messaging")
    Rel(ws_hub, redis, "Updates ticks", "Redis Protocol")
```

## Containers
- **Web App**: Rails API mode with a Vue.js frontend for dashboard visualization.
- **Trading Daemon**: A long-running Ruby process managed by a `Supervisor` that ticks every 30-60 seconds to evaluate signals.
- **Market Feed Hub**: A dedicated thread/process maintaining an active WebSocket connection to DhanHQ.
- **Redis**: The "live" state, essential for sub-second risk decisions.
- **PostgreSQL**: The "audit" state, used for long-term storage and analytical reporting.
