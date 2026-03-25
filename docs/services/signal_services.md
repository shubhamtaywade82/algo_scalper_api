# Signal & Strategy Services

Detailed documentation for services within the `Signal::` namespace.

## Signal::Engine

**File:** `app/services/signal/engine.rb`

**Purpose:**
The core brain of the system. It analyzes technical indicators (Supertrend, ADX, SMC) for a given index and decides whether to generate a buy (bullish) or sell (bearish) signal.

**Inputs:**
- `index_cfg`: Hash containing symbol, timeframe, and logic parameters.
- Instrument data (Candle series).

**Outputs:**
- `TradingSignal` record (persisted).
- Calls `Options::ChainAnalyzer` to qualify strikes.
- Calls `Entries::BosEntryEngine` or `EntryGuard` to attempt entry.

**Dependencies:**
- `Indicators::Supertrend`
- `Indicators::ADX`
- `Signal::StateTracker`
- `Trading::PermissionResolver`

**Used by:**
- `Signal::Scheduler`

### Market context (optional)

When `market_context.enabled` is true in `config/algo.yml`, after qualified option `picks` exist, `Signal::Engine` calls `evaluate_market_context_for_entry` (private helper in `app/services/signal/engine.rb`):

| Component | File | Role |
|-----------|------|------|
| `MarketContext::RegimeComposer` | `app/services/market_context/regime_composer.rb` | Builds `RegimeSnapshot` using `MarketRegimeDetector` + structure/volatility/participation analyzers. |
| `Options::ChainSignalExtractor` | `app/services/options/chain_signal_extractor.rb` | Chain-side confirmation (flow, PCR, premium expansion vs cache). |
| `Trading::MarketPermissionGate` | `app/services/trading/market_permission_gate.rb` | Optional hard gate when `market_context.gate.enabled` is true. |
| `Trading::StrategyProfileSelector` | `app/services/trading/strategy_profile_selector.rb` | Maps snapshot → `strategy_profile` symbol stored in `entry_metadata` and tracker `meta`. |

**Docs:** `docs/trading/market_context_and_permission_gate.md`

---

## Signal::Scheduler

**File:** `app/services/signal/scheduler.rb`

**Purpose:**
A long-running background service that orchestrates the execution of `Signal::Engine` across all configured indices at regular intervals.

**Inputs:**
- `period`: Cycle interval (default: 30s).
- Index configuration from `algo.yml`.

**Outputs:**
- Periodic heartbeats to `Live::SystemStatusCache`.
- Sequential execution of `Signal::Engine.run_for(index)`.

**Dependencies:**
- `IndexConfigLoader`
- `TradingSession::Service`
- `Signal::Engine`

**Used by:**
- `TradingSystem::Supervisor`

---

## Signal::TrendScorer

**File:** `app/services/signal/trend_scorer.rb`

**Purpose:**
Performs multi-timeframe trend analysis to provide a "Confidence Score" for a potential trade.

**Inputs:**
- `index_cfg`: The index to score.

**Outputs:**
- A numeric score (0-100) representing trend strength.
- Recommended direction based on confluence.

**Dependencies:**
- `IndexTechnicalAnalyzer`
- `Indicators::RSI`
- `Indicators::MACD`

**Used by:**
- `Signal::Engine`
- `Signal::Scheduler`
