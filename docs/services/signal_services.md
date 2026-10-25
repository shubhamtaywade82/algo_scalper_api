# Signal & Strategy Services

Detailed documentation for services within the `Signal::` namespace and related signal-layer components.

---

## Signal::Engine

**File:** `app/services/signal/engine.rb`

**Purpose:**
The core signal generation brain. Analyzes technical indicators (Supertrend, ADX, SMC) for a given index across 13 numbered steps and decides whether to generate a bullish or bearish signal.

**Inputs:**
- `index_cfg`: Hash containing key, segment, SID, timeframe, ADX thresholds, and logic parameters
- Instrument data from `IndexInstrumentCache` (candle series via DhanHQ API)
- Current `AlgoConfig.run_mode`

**Outputs:**
- `TradingSignal` record (persisted with full diagnostic metadata)
- Calls `Options::ChainAnalyzer` to qualify strikes
- Calls `Entries::BosEntryEngine` or `Entries::EntryGuard` to attempt entry

**Steps:**
1. Market open check
2. Instrument resolution
3. Analysis context initialization (respects `run_mode`)
4. Primary + confirmation analysis
5. Trading context gate (EntryFilterEngine, PermissionResolver)
6. Entry quality filter
7. Institutional gates (SMC, momentum)
8. State snapshot dedup
9. Options analysis
10. Diagnostic metadata build
11. TradingSignal persistence
12. Optional market context gate
13. Entry trigger

**Run mode behavior:**

| Mode | entry_primary | primary_tf | confirmation | quality gates |
|------|--------------|------------|-------------|---------------|
| `production` | from config | from config | from config | full |
| `exit_testing` | `supertrend_adx` (forced) | `1m` (forced) | disabled | most bypassed |
| `entry_testing` | from config | from config | from config | relaxed |

**Dependencies:** `Indicators::Supertrend`, `Indicators::ADX`, `Signal::StateTracker`, `Trading::PermissionResolver`, `Entries::EntryFilterEngine`, `Options::ChainAnalyzer`

**Used by:** `Signal::Scheduler`

### Market Context (Optional)

When `market_context.enabled: true`, `MarketContext::RegimeComposer` builds a
`RegimeSnapshot` from the primary candle series. The snapshot is consumed by
AI/agent paths (`Ai::Agents::MarketAnalysisAgent`,
`Ai::DynamicConfig::ContextBuilder`, `OptionsBuying::TradeScoringEngine`),
not by `Signal::Engine` directly.

> **Note (2026-10-25):** The previous version of this section described a
> `Signal::Engine#evaluate_market_context_for_entry` flow that wired
> `ChainSignalExtractor`, `MarketPermissionGate`, and
> `StrategyProfileSelector` into the entry pipeline. Those components were
> removed as dead code in audit S-001 — see
> `docs/trading/market_context_and_permission_gate.md` for details.

| Component | File | Role |
|-----------|------|------|
| `MarketContext::RegimeComposer` | `app/services/market_context/regime_composer.rb` | Builds `RegimeSnapshot` (structure + volatility + participation → conviction_score) |

**Docs:** `docs/trading/market_context_and_permission_gate.md`

---

## Signal::Scheduler

**File:** `app/services/signal/scheduler.rb`

**Purpose:**
Long-running background service that orchestrates `Signal::Engine` across all configured indices at regular 30-second intervals.

**Inputs:**
- `period`: Cycle interval (default: 30s)
- Index configurations from `algo.yml`

**Behavior:**
- Runs as singleton (prevents duplicate signal threads)
- Iterates over configured indices in order (NIFTY, BANKNIFTY, SENSEX)
- Skips indices where market is closed
- Filters indices by expiry proximity (`signals.max_expiry_days: 7`)
- Provides heartbeat to `Live::SystemStatusCache`

**Dependencies:** `IndexConfigLoader`, `TradingSession::Service`, `Signal::Engine`

**Used by:** `TradingSystem::Supervisor`

---

## Signal::TrendScorer

**File:** `app/services/signal/trend_scorer.rb`

**Purpose:**
Computes multi-timeframe trend score (0-21) used for dynamic risk allocation and entry quality assessment.

**Inputs:**
- Candle series for multiple timeframes
- Index configuration

**Outputs:**
- Numeric score (0-21) representing trend strength and conviction
- Recommended direction based on confluence

**Scoring components:**
- Supertrend alignment across timeframes
- ADX strength
- RSI momentum
- MACD signal

**Used by:** `Signal::Engine`, `Capital::DynamicRiskAllocator`

---

## Signal::StateTracker

**File:** `app/services/signal/state_tracker.rb`

**Purpose:**
Prevents redundant signal generation and manages per-index signal deduplication.

**Logic:**
- Records last signal: `(index_key, direction, candle_timestamp)`
- `record(...)` returns existing state if same direction+candle; creates new snapshot otherwise
- `reset(index_key)` clears state for an index (called when context gate blocks)

**Used by:** `Signal::Engine`

---

## Signal::MomentumValidator

**File:** `app/services/signal/momentum_validator.rb`

**Purpose:**
Scores momentum 0-3 from recent price action. Used as a quality filter for entry decisions.

**Used by:** `Signal::Engine` (step 7 — institutional gates)

---

## Trading::PermissionResolver

**File:** `app/services/trading/permission_resolver.rb`

**Purpose:**
SMC + AVRZ-based permission gating. Returns `:allowed`, `:blocked`, or `:neutral` based on SMC decision alignment and AVRZ zone analysis.

**Config toggles:**
- `signals.enable_smc_avrz_permission` (default true)
- `signals.enable_smc_decision_alignment` (default true)

**Used by:** `Signal::Engine` (step 5 — trading context gate)

---

## Entries::EntryFilterEngine

**File:** `app/services/entries/entry_filter_engine.rb`

**Purpose:**
Pre-guard institutional filter for structure/liquidity/volatility alignment. Runs before the guard pipeline.

**Checks:**
- Price structure validity
- Liquidity conditions
- Volatility alignment with strategy type

**Config toggle:** `signals.entry_filter.enabled` (or always on depending on config)

**Used by:** `Signal::Engine` (step 5 — trading context gate)

---

## IndexInstrumentCache

**File:** `app/services/index_instrument_cache.rb` (or similar)

**Purpose:**
In-memory cache for index instrument records. Avoids repeated DB queries during the 30s signal cycle.

**Used by:** `Signal::Engine`, `Signal::Scheduler`

---

## Configuration

Signal behavior controlled by `config/algo.yml` under `signals:`:

```yaml
signals:
  entry_strategy:
    primary: supertrend_adx     # 'supertrend', 'supertrend_adx', 'index_ta'
  primary_timeframe: 5m
  confirmation_timeframe: 1m
  enable_confirmation_timeframe: true
  validation_mode: balanced       # 'balanced' or 'conservative'
  max_expiry_days: 7              # skip instruments with expiry > 7 days

  # SMC gating (default: true)
  enable_smc_decision_alignment: true
  enable_smc_avrz_permission: true

  # Optional TA filter (default: false)
  enable_index_ta_filter: false
  ta_min_confidence: 0.6
```

Per-index ADX thresholds in `indices[].min_adx_entry` (varies: NIFTY ~15, BANKNIFTY ~18, SENSEX ~15).
