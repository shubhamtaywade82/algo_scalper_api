# AlgoScalperApi: Complete Feature Directory

This document details the functional features, architectural subsystems, and capabilities of the `algo_scalper_api` algorithmic index options scalping system.

---

## 1. Broker Integration & Auth Gateway
*   **DhanHQ REST Wrapper**: Complete REST integration covering funds, margins, positions, order placements (LIMIT, MARKET, SL, SL-M), and daily security master database imports.
*   **Websocket Ingestion Feed**: High-performance, fault-tolerant `Live::MarketFeedHub` managing real-time index tick feeds, connection watchdogs, and stream buffers.
*   **Polymorphic Authentication Gateway**: Centralized `TokenManager` supporting four runtime strategies:
    *   `totp`: Automated login generating TOTP tokens via `rotp` and Pin validation.
    *   `manual`: Override token configuration from environment variables.
    *   `renew`: Extends live session tokens via the broker's token renewal API.
    *   `authority`: Delegates credentials management to an external oauth server.

---

## 2. Options Analytics & Execution
*   **Option Chain Analyzer**: Calculates dynamic Atm strike brackets, bid-ask spreads, liquidity thresholds, Open Interest (OI) changes, and Greeks (Delta, Gamma, Vega, Theta).
*   **Greeks Acceleration Detectors**:
    *   `GammaRampDetector`: Pinpoints strike price ranges experiencing accelerated gamma expansion.
    *   `DeltaAccelerationDetector`: Evaluates momentum based on delta movement speeds.
*   **Expired Options Backtesting**: Historical premium fetcher (`Options::ExpiredFetcher`) retrieves actual 5-minute OHLC candles of expired option contracts from the broker.
*   **Large Order Slicing**: `Orders::Slicer` segments quantities exceeding exchange freeze limits into sequential blocks.

---

## 3. Market Intelligence & Decision Engines
*   **Regime Classifier**: Categorizes index trading behavior into `:trending`, `:ranging`, `:low_vix`, or `:event_day` parameters.
*   **Smart Money Concepts (SMC) Scanner**: Parses raw index candle history to map:
    *   Market structure breaks (BOS/CHOCH)
    *   FVG (Fair Value Gaps) and order blocks
    *   Liquidity sweeps and pullback thresholds
*   **Trade Scoring Engine**: Compiles a composite setup score (0–100) combining structural confluence, VIX, participation index, and ADX/Supertrend alignment.
*   **Generative AI Alpha Gate**: Ollama-backed [AlphaGate](file:///app/services/ai/alpha_gate.rb) acts as an automated risk check, prompting local open-weights models to ALLOW or BLOCK trading signals.

---

## 4. Multi-Tier Risk Guardrails & Circuit Breakers
*   **Exposure Controls**:
    *   `DailyLimitsGuard`: Enforces maximum daily capital exposure.
    *   `ExposureGuard`: Rupee-based position capital limit.
    *   `SizingGuard`: Sizes orders dynamically using rolling Kelly expectancy ratios.
*   **Session Guardians**:
    *   `TradingTimeRestrictionGuard`: Intraday hours gate (stops entries after closing buffers).
    *   `EarliestEntryGuard`: Blocks volatile market opening ticks.
    *   `LtpResolutionGuard`: Drops signals if tick timestamps are delayed (latency filter).
*   **Loss Protections**:
    *   `DrawdownGuard`: Disables trading if daily losses breach absolute limits.
    *   `Live::ExitEngine`: Enforces trailing stops, breakeven triggers, and profit floors.

---

## 5. Ledger & Accounting
*   **Double-Entry Ledger Engine**: Tracks all financial items in real-time.
    *   `LedgerAccount`: Segregates cash, margins, and realized P&L balances.
    *   `LedgerJournalEntry`: Records transactional journals.
    *   `LedgerPosting`: Double-entry balance accounting entries.

---

## 6. Autonomous Learning & Parameter Solvers
*   **Observe-Think-Act Orchestrator**: Runs EOD audits evaluating win rates, drawdowns, and MAE/MFE ratios.
*   **Indicator Optimizer**: Automatically executes parameter grid sweeps to optimize ADX/Supertrend parameters.
*   **Trailing Optimizer**: Tunes trailing stop distances, breakeven points, and activation triggers based on historical trade telemetry.

---

## 7. Real-Time Observability Dashboard
*   **ActionCable WebSocket Broadcasts**: Streams real-time position trackers, open P&L, segment LTPs, and system settings to frontend clients.
*   **Vite + Solid.js UI**: Sleek dark-mode interface exposing:
    *   Regime details, SMC confluences, and active trade logs.
    *   Expected value risk explorers and stop-loss calibrations.
    *   An interactive backtesting control panel to execute parameter optimization sweeps.
