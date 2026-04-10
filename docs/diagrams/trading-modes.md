# Trading Modes Flow Diagrams

Mermaid diagrams for how **automated trading modes** combine in Algo Scalper API. Modes are
orthogonal: **effective algo config** (YAML + DB + signal tier + `LIVE_TRADING`), paper vs live
gateway, live order safety (`PLACE_ORDER` + `dhanhq.enable_orders`), and daemon environment
flags.

See also: [Architecture diagrams index](../architecture/diagrams/README.md),
`config/algo.yml`, `config/signal_tier_presets.yml`, `app/lib/algo_config.rb`,
`app/services/signal/engine.rb`, `app/services/orders/gateway_factory.rb`.

---

## Configuration Stack (Effective `AlgoConfig.fetch`)

Effective config is built in this order (each step deep-merges into the previous):

1. `config/algo.yml`
2. DB `settings.algo_config_overrides` (JSON)
3. Overlay from `config/signal_tier_presets.yml` for the active tier
4. `LIVE_TRADING` env forces `paper_trading.enabled` (see below)

```mermaid
flowchart TB
  subgraph cfg [Config load — AlgoConfig.fetch]
    A[config/algo.yml] --> M1[Deep merge]
    D[(Settings: algo_config_overrides JSON)] --> M1
    M1 --> M2[Deep merge signal tier preset]
    T["config/signal_tier_presets.yml\nexploratory | standard | selective"] --> M2
    M2 --> LT[LIVE_TRADING env → paper_trading.enabled]
    LT --> C[Effective config + 30s cache]
  end

  subgraph tier [Signal tier resolution]
    E["ENV SIGNAL_TIER"] --> R{valid tier?}
    R -->|yes| TI[use ENV]
    R -->|no| Y[signals.signal_tier in merged YAML]
    Y --> TI2{valid?}
    TI2 -->|yes| TI
    TI2 -->|no| STD[standard]
    TI --> M2
    STD --> M2
  end
```

---

## LIVE_TRADING And Paper Vs Live Gateway

`LIVE_TRADING` is evaluated after tier merge. When unset or false, **`paper_trading.enabled` is
forced true** (paper). When true, **`paper_trading.enabled` is forced false** (live gateway path).
`dhanhq.enable_orders` and `PLACE_ORDER` still gate actual broker submission on live.

```mermaid
flowchart LR
  subgraph boot [Rails boot]
    F[Orders::GatewayFactory.build] --> Q{effective paper_trading.enabled == true?}
    Q -->|yes| GP[GatewayPaper — synthetic fills at LTP]
    Q -->|no| GL[GatewayLive — DhanHQ REST]
  end

  subgraph place [Each market order — GatewayLive only]
    GL --> PL[Orders::Placer]
    PL --> S1{dhanhq.enable_orders?}
    S1 -->|no| DR[dry-run log]
    S1 -->|yes| S2{PLACE_ORDER == true?}
    S2 -->|no| DR
    S2 -->|yes| API[DhanHQ API]
    GP --> SIM[Simulated fill + local position updates]
  end
```

---

## Signal Engine: Single Pipeline

There is **no** `run_mode` / `exit_testing` branch. Strategy and strictness come from merged YAML
and tier preset (e.g. `signals.entry_strategy`, `signals.validation_modes`,
`halt_on_validation_failure`, gates).

```mermaid
flowchart TD
  START[Signal::Engine.run_for] --> TRAD{Tradable session?}
  TRAD -->|no| STOP1[return]
  TRAD -->|yes| INST{Instrument ok?}
  INST -->|no| STOP1
  INST -->|yes| BR{entry_primary == supertrend?}
  BR -->|yes| ST[supertrend-only flow + regime-based effective_validation_mode]
  BR -->|no| STD2[standard / multi-indicator flow]
  ST --> HALT{halt_on_validation_failure + validation failed?}
  STD2 --> HALT
  HALT -->|yes| RST[reset StateTracker, return]
  HALT -->|no| TC[Trading context gate]
  TC -->|blocked| RST
  TC -->|pass| EQ[Entry quality filter]
  EQ -->|fail| RST
  EQ -->|pass| NT[No-trade gate + DTE guard]
  NT -->|fail| RST
  NT -->|pass| EG[Execution gates — SMC, momentum, etc.]
  EG -->|fail| RST
  EG -->|pass| OA[Options analysis + optional options_analysis_gate]
  OA --> ENT[Entry gate + trigger_entry_flow]
```

---

## Live Order Updates: Paper Trackers Ignored

WebSocket order updates adjust live trackers only; paper positions are owned by `GatewayPaper`.

```mermaid
flowchart TD
  WS[Dhan order update WebSocket] --> H[Live::OrderUpdateHandler]
  H --> T{tracker.paper?}
  T -->|yes| SKIP[Ignore — GatewayPaper owns lifecycle]
  T -->|no| UPD[Update tracker / mark_exited on SELL fill etc.]
```

---

## Trading Daemon: High-Level Automation Loop

Requires `ENABLE_TRADING_SERVICES=true`. Certain env flags suppress the trading brain or feed
behaviour (see `lib/trading_system/daemon.rb`, `Live::MarketFeedHub`).

```mermaid
flowchart TD
  subgraph guard [Process guards]
    E1[ENABLE_TRADING_SERVICES=true] --> D[trading:daemon / supervisor]
    E2{BACKTEST_MODE or SCRIPT_MODE?} -->|blocks| NOSTART[Trading brain services not started / feed limited]
  end

  D --> MF[MarketFeedHub — ticks]
  D --> SS[Signal::Scheduler ~30s]
  SS --> SE[Signal::Engine]
  SE --> EG[Entries::EntryGuard + guards pipeline]
  EG --> GW[Gateway Paper or Live]
  GW --> PT[PositionTracker + feed subscription]

  PT --> RM2[RiskManager + UnifiedExitChecker]
  RM2 --> EE[Exit path → gateway exit order]
  EE --> GW
```

---

## Signal Tier Quick Reference

| Tier | Source | Intent |
|------|--------|--------|
| `exploratory` | `SIGNAL_TIER=exploratory` or `signals.signal_tier` | Overlay from preset YAML — most permissive for research/paper |
| `standard` | Default when tier missing/invalid | Preset may be empty — behaviour matches `algo.yml` + DB as merged |
| `selective` | `SIGNAL_TIER=selective` or YAML | Stricter overlay from preset (not a profit guarantee) |

Tier choice does **not** switch gateways; use **`LIVE_TRADING=true`** for live gateway selection
at boot (restart required after change).
