# Trading Modes Flow Diagrams

Mermaid diagrams for how **automated trading modes** combine in Algo Scalper API. Modes are
orthogonal: run profile (`RUN_MODE` + YAML profile), paper vs live gateway, live order safety
(`PLACE_ORDER`), and daemon / safety environment flags.

See also: [Architecture diagrams index](../architecture/diagrams/README.md),
`config/algo.yml`, `config/profiles/*.yml`, `app/lib/algo_config.rb`,
`app/services/signal/engine.rb`, `app/services/orders/gateway_factory.rb`.

---

## Configuration Stack And Run Mode

Effective algo config is built from base YAML, an optional profile keyed by `run_mode`, and DB
overrides. `Signal::Engine` only special-cases `run_mode == exit_testing` in Ruby; `entry_testing`
relies on merged YAML (relaxed thresholds, flags).

```mermaid
flowchart TB
  subgraph cfg [Config load — AlgoConfig.fetch]
    A[config/algo.yml] --> M[Deep merge]
    P["config/profiles/{run_mode}.yml\nproduction | exit_testing | entry_testing"] --> M
    M --> D[(Settings: algo_config_overrides JSON)]
    D --> C[Effective config + 30s cache]
  end

  subgraph rm [Run mode resolution]
    E["ENV RUN_MODE"] --> R{present?}
    R -->|yes| RM[use ENV value]
    R -->|no| Y[algo.yml run_mode]
    Y --> RM
    RM --> P
  end

  subgraph sig [Signal code branch]
    RM --> SE["AlgoConfig.run_mode"]
    SE --> X{run_mode == exit_testing?}
  end
```

---

## Signal Engine: Exit Testing Vs Production And Entry Testing

`production` and `entry_testing` share the same pipeline; profile YAML differs.
`exit_testing` forces a faster path (e.g. 1m primary, skips several gates).

```mermaid
flowchart TD
  START[Signal::Engine.run_for] --> TRAD{Tradable session?}
  TRAD -->|no| STOP1[return]
  TRAD -->|yes| INST{Instrument ok?}
  INST -->|no| STOP1
  INST -->|yes| RM{run_mode == exit_testing?}

  subgraph exit_test [Exit testing path]
    RM -->|yes| CTX1[Context: supertrend_adx on 1m, no confirmation TF]
    CTX1 --> FLOW1[Standard / supertrend analysis flow]
    FLOW1 --> V1[effective_validation_mode = exit_testing]
    V1 --> TC1{Trading context gate?}
    TC1 -->|blocked| STOP2[reset state, return]
    TC1 -->|pass / skipped if no regime_state| EQ1[Entry quality: SKIPPED]
    EQ1 --> EG1[Execution gates: SKIPPED — filter, permission, SMC, momentum]
    EG1 --> OPT1[Options analysis]
  end

  subgraph normal [Production + entry_testing path]
    RM -->|no| CTX2[Context from signals config + profile merge]
    CTX2 --> FLOW2[Analysis flows per entry_primary]
    FLOW2 --> V2[validation_mode from config / flow]
    V2 --> TC2{Trading context gate enabled and blocked?}
    TC2 -->|yes| STOP3[reset, return]
    TC2 -->|no| EQ2[EntryQualityFilter]
    EQ2 -->|fail| STOP3
    EQ2 -->|pass| EG2[EntryFilterEngine + PermissionResolver + SMC + momentum]
    EG2 -->|fail| STOP3
    EG2 -->|pass| OPT2[Options analysis]
  end

  OPT1 --> META[Metadata + persist signal → downstream entries]
  OPT2 --> META
```

---

## Order Execution: Paper Vs Live And Place Order Gate

Gateway is chosen at boot (`Orders::GatewayFactory`). Live orders still require `PLACE_ORDER`
(and `dhanhq.enable_orders` per deployment docs) or the placer dry-runs.

```mermaid
flowchart LR
  subgraph boot [Rails boot]
    F[Orders::GatewayFactory.build] --> Q{paper_trading.enabled == true?}
    Q -->|yes| GP[GatewayPaper — synthetic fills at LTP]
    Q -->|no| GL[GatewayLive — DhanHQ REST]
  end

  subgraph place [Each market order]
    GL --> PL[Orders::Placer]
    PL --> S{PLACE_ORDER == true?}
    S -->|no| DR[dry-run log — no broker call]
    S -->|yes| API[DhanHQ API]
    GP --> SIM[Simulated fill + local position updates]
  end
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
    E2{BACKTEST_MODE or SCRIPT_MODE or DISABLE_TRADING_SERVICES?} -->|blocks| NOSTART[Trading brain services not started / feed limited]
  end

  D --> MF[MarketFeedHub — ticks]
  D --> SS[Signal::Scheduler ~30s]
  SS --> SE[Signal::Engine — mode as above]
  SE --> EG[Entries::EntryGuard + guards pipeline]
  EG --> GW[Gateway Paper or Live]
  GW --> PT[PositionTracker + feed subscription]

  PT --> RM2[RiskManager + UnifiedExitChecker]
  RM2 --> EE[Exit path → gateway exit order]
  EE --> GW
```

---

## Profile Files Quick Reference

| Profile (`config/profiles/`) | Code path in `Signal::Engine` | Main intent |
|------------------------------|--------------------------------|-------------|
| `production.yml` | Full pipeline (same as base) | Default real / paper evaluation behaviour. |
| `exit_testing.yml` | **`exit_testing` branch** + merged YAML | Many more entries; stress-test exits. |
| `entry_testing.yml` | Full pipeline, relaxed merged YAML | More signals through guards; test entry path. |

Set via `run_mode` in `config/algo.yml` or `ENV RUN_MODE` (see `.env.example`).
