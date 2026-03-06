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
