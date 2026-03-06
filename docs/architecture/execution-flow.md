# Trade Lifecycle: Signal to Execution

This document traces the end-to-end path of a trade from the initial signal trigger to the final exit order.

## 1. Trigger & Analysis
- **Service**: `Signal::Scheduler` & `Signal::Engine`
- **Action**: Every tick or at fixed intervals, the scheduler triggers the Engine for active indices.
- **Result**: A **Signal** is generated if technical conditions (Supertrend, ADX, SMC) are met.

## 2. Option Strike Selection
- **Service**: `Options::ChainAnalyzer`
- **Action**: For a bullish signal, identifies the optimal CALL strike; for bearish, the optimal PUT strike.
- **Criteria**: Based on `strike_selection_mode` (e.g., `atm`, `closest_premium`) in `config/algo.yml`.

## 3. Entry Guard (The Gatekeeper)
- **Service**: `Entries::EntryGuard`
- **Action**: Performs critical pre-trade checks before the order is sent to the broker.
- **Validations**:
    - **Circuit Breaker**: System-wide halt check.
    - **Exposure**: Checks current capital usage and "rupees at risk".
    - **Cooldown**: Prevents over-trading the same symbol.
    - **Daily Limits**: Verifies remaining daily profit/loss capacity.
    - **LTP Resolution**: Resolves the latest price from `MarketFeedHub`.

## 4. Entry Management
- **Service**: `Orders::EntryManager`
- **Action**: Wraps the entry request, calculates Initial Stop-Loss (SL) and Take-Profit (TP) levels.
- **Persistence**: Creates a `PositionTracker` record in `pending` status.

## 5. Order Placement
- **Service**: `TradingSystem::OrderRouter` -> `Orders::Placer` (Live) or `Paper::Engine`
- **Action**: Sends the payload to DhanHQ API or executes simulated paper entry.
- **Result**: `PositionTracker` updated to `active` status with `order_no` and `avg_price`.

## 6. Live Monitoring
- **Service**: `Live::RiskManagerService`
- **Action**: Runs every 1-5 seconds to monitor the open position.
- **Data**: Reads real-time PnL from `Live::RedisPnlCache` (populated by `MarketFeedHub`).

## 7. Exit Evaluation
- **Service**: `Live::UnifiedExitChecker`
- **Action**: Evaluates the position against defined exit rules in priority order:
    1.  **Early Trend Failure (ETF)**: Trend reversal detection.
    2.  **Hard SL**: Rupee/Percentage based stop loss.
    3.  **Hard TP**: Target profit reached.
    4.  **Trailing Stop**: Dynamic SL adjustment.
    5.  **Time Stop**: Exit at specific session close times.

## 8. Execution & Cleanup
- **Service**: `Live::ExitEngine`
- **Action**: Places the closing order via `OrderRouter`.
- **Cleanup**:
    - Unsubscribes from the instrument feed in `MarketFeedHub`.
    - Updates `PositionTracker` to `exited`.
    - Persists final PnL to the database.
