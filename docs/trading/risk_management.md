# Risk Management & Exit Rules

The system employs a multi-layered risk management strategy, prioritizing capital preservation through a prioritized exit hierarchy.

## The Exit Hierarchy

All active positions are evaluated every 1-5 seconds by the `RiskManagerService`. The `Live::UnifiedExitChecker` evaluates conditions in the following strict priority order:

| Priority | Exit Rule | Description |
| :--- | :--- | :--- |
| 1 | **Early Trend Failure (ETF)** | Detects trend reversal *before* SL is hit, using multi-timeframe candle patterns. |
| 2 | **Hard Stop-Loss (SL)** | Static or Adaptive SL based on rupee value or percentage drawdown. |
| 3 | **Take-Profit (TP)** | Fixed profit target as defined in configuration. |
| 4 | **Trailing Stop** | Bidirectional trailing (Adaptive or Fixed) that locks in profits as price moves favorably. |
| 5 | **Time-Based Exit** | Forces closure at specific times (e.g., 3:20 PM) to avoid overnight risk. |

## Specialized Loss Protection

### 1. Early Trend Failure (ETF)
- **Logic**: If the trend that triggered the entry reverses (e.g., Supertrend flip on 1m timeframe), the position is exited early to minimize loss.
- **Toggle**: `exit: early_exit: enabled: true`

### 2. Adaptive Stop-Loss
- **Logic**: Uses `Positions::DrawdownSchedule` to adjust the allowed loss based on how long the position has been held and the current volatility (ATR ratio).
- **Goal**: Tighten stops for "stagnant" trades that stay below entry price for too long.

### 3. Bidirectional Trailing Stops
- **Upward Trailing**: Moves the SL up as profit increases.
- **Downward Trailing (Adaptive)**: Dynamically calculates the "allowed drop" from peak profit using a schedule rather than a fixed percentage.
- **Activation**: Trailing typically activates only after a `min_profit` or `activation_profit` threshold is reached.

## Configuration
Controlled under the `exit:` key in `config/algo.yml`:
- `stop_loss`: Static value or `adaptive` type.
- `trailing`: Parameters for activation and drop thresholds.
- `time_based`: Market close exit times.
