# Risk Management & Exchange Support Review

## Summary Of Findings
- The live risk loop only enforces trailing stops and a daily loss breaker, leaving the
  configured stop-loss, take-profit, and per-trade risk settings unused in production
  flows.
- Options strike selection always tags orders as `NSE_FNO`, so BSE_FNO contracts (for
  example, SENSEX weekly options) will be placed against the wrong exchange segment.
- Temporary index instruments created from `config/algo.yml` default to NSE, which means
  SENSEX can be misclassified unless the BSE record already exists in the database.
- Operational self-sufficiency still depends on DhanHQ data availability for funds,
  positions, and market data; loss of those feeds leaves the risk loop blind.

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
| Per-trade risk sizing | `risk.per_trade_risk_pct` | Not Enforced | No call sites reference this key; `RiskManagerService` ignores it. |
| Hard stop-loss / take-profit | `risk.sl_pct`, `risk.tp_pct` | Not Enforced | No exit logic uses these percentages, so runaway losses remain possible. |

> **Warning:** Without hard stop-loss enforcement, a connectivity lapse between the app
> and DhanHQ can allow deep drawdowns because only trailing logic reacts, and it depends
> on live ticks and existing `PositionTracker` rows.

## Exchange Coverage Assessment
- `Options::ChainAnalyzer` injects `segment: "NSE_FNO"` for every selected leg, which
  will break BSE_FNO execution even if the derivative metadata is present because order
  entry will hit the wrong exchange code.
- `IndexInstrumentCache` assumes `IDX_I` implies NSE when constructing a fallback
  `Instrument`, so SENSEX requests issued before BSE indices are imported will inherit
  the NSE exchange and ultimately fetch NSE option chains.
- Position tracking and exit logic pull quotes from `Live::TickCache`. If the WebSocket
  subscription for a BSE security fails (because the segment is mislabelled), trailing
  exits will never trigger despite open exposure.

## Recommended Fixes
1. Wire `risk.per_trade_risk_pct`, `risk.sl_pct`, and `risk.tp_pct` into the live exit
   loop with deterministic stop orders so that losses cap even when trailing logic does
   not fire.
2. Carry the derivative`s `exchange_segment` through `Options::ChainAnalyzer` and
   `Entries::EntryGuard` so NSE_FNO and BSE_FNO legs route to their native exchanges.
3. Extend `IndexInstrumentCache#determine_exchange` to recognise BSE index segments and
   pre-seed SENSEX derivative metadata to avoid defaulting to NSE.
4. Add health assertions for required DhanHQ feeds (funds, positions, ticks) and block
   order placement when any source is stale to maintain operational safety.
