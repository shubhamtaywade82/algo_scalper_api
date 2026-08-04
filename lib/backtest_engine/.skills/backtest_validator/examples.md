# Backtest Validator Examples

Here are concrete examples showing how the auditor detects lookahead bias and fills validation errors.

## Example 1: Detecting Lookahead Bias

### Scenario
* A strategy triggers an entry signal when:
  `indicators[:rsi] > 60 && index_candle.close > indicators[:ema_20]`
* In the backtest trade log, a buy trade is executed at:
  - Timestamp: `2026-07-09T09:30:00+05:30`
  - Fill Price: `142.0` (matching the close of the 09:30 candle)
* Validation Audit check:
  - The 09:30 candle is the *current* candle during which the signal is evaluated. The close of this candle is not physically known until `09:30:00`.
  - Buying at `142.0` at exactly `09:30:00` assumes zero latency and perfect execution at the closing tick.
  - Verdict: **Lookahead Bias / Execution Realism Failure**. The entry should execute on the *next* candle (e.g. `09:31` open) or include slippage.

---

## Example 2: Non-Monotonic Stop Loss Failure

### Scenario
* Audit scanning the trailing stop records:
  - Trade Entry at `100.0`
  - Stop at `T0`: `80.0`
  - Stop at `T1` (Price rises to 120.0): Stop moved to `100.0`
  - Stop at `T2` (Price drops to 110.0): Stop moved to `90.0` (widened to avoid exit)
* Verdict: **Audit Failure (Monotonicity Violation)**. Stop loss was widened during the trade. This indicates a programming bug in the trailing logic and rejects the backtest.
