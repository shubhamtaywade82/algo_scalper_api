# Risk Management & Exchange Support Review

## Summary Of Findings
- The live risk loop now enforces per-trade loss caps, hard stop-loss, and take-profit
  exits in addition to the existing trailing and daily circuit protections.
- Options strike selection carries the derivative-provided exchange segment so NSE_FNO
  and BSE_FNO contracts route to the proper venue.
- Index cache creation recognises BSE indices (for example, SENSEX) and seeds the
  correct exchange metadata while entry flow blocks orders when DhanHQ feeds turn stale.

## Validation Steps
1. Reviewed `config/algo.yml` to catalogue available risk configuration switches and
   their intended thresholds.
2. Traced the `Live::RiskManagerService` code paths to confirm which controls are
   actually executed inside the 5-second loop.
3. Followed the options strike picker through `Options::ChainAnalyzer` to observe how
   the segment and security identifiers are propagated into order placement.
4. Inspected index caching fallbacks inside `IndexInstrumentCache` to understand how
   indices without seeded metadata are classified.

## Risk Control Assessment
| Control | Config Reference | Implementation Status | Notes |
| --- | --- | --- | --- |
| Daily loss breaker | `risk.daily_loss_limit_pct` | Enforced | Trips the circuit breaker when the net balance drawdown exceeds the threshold. |
| Trailing stop / breakeven | `risk.trail_step_pct`, `risk.breakeven_after_gain`, `risk.exit_drop_pct` | Enforced | Executes exits through `RiskManagerService` when high-water marks roll over. |
| Per-trade risk sizing | `risk.per_trade_risk_pct` | Enforced | Hard exits trigger once realised loss exceeds the configured allocation relative to deployed capital. |
| Hard stop-loss / take-profit | `risk.sl_pct`, `risk.tp_pct` | Enforced | Deterministic exit prices terminate exposure even if live ticks stop updating the trailing logic. |
| Feed health guard | N/A | Enforced | Entry flow raises when funds, positions, or tick feeds fall behind the safety thresholds. |

> **Warning:** Configure realistic stop-loss and take-profit percentages per index; overly
> tight thresholds can over-trigger exits while wide bands weaken the new deterministic
> guards.

## Exchange Coverage Assessment
- `Options::ChainAnalyzer` now preserves the derivative-provided `exchange_segment`, so
  NSE_FNO and BSE_FNO orders are tagged correctly when they reach `Orders::Placer`.
- `IndexInstrumentCache` seeds BSE indices with the `BSE_IDX` exchange segment when the
  database has not been pre-populated, eliminating the previous misclassification of
  SENSEX as NSE.
- Position tracking still depends on real-time ticks, but the entry guard blocks orders
  when the tick feed is stale, reducing the chance of running blind exposure.

## Follow-Up Actions
1. Validate the configured stop-loss and take-profit percentages for each index with
   broker-side bracket or cover orders to keep platform and exchange risk controls in
   sync.
2. Extend automated tests to cover feed-health degradation scenarios (for example, mock
   tick droughts) so future changes cannot regress the guard rails.
3. Periodically review derivative metadata in the database to ensure lot sizes and
   exchange segments stay aligned with circular updates from NSE and BSE.
