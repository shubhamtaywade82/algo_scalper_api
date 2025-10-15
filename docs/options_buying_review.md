# Options Buying Readiness Review

## Scope
- Assessed NIFTY, BANKNIFTY, and SENSEX support for option buying.
- Evaluated open-position handling against live broker state.
- Stress-tested risk controls across NSE_FNO and BSE_FNO venues.

## Review Steps
1. Trace index instrument caching and option-chain selection flow.
2. Inspect entry guard, tracker lifecycle, and market feed wiring.
3. Analyse live risk loop for stop, loss-limit, and circuit breaker logic.
4. Cross-check capital allocation inputs against risk guard calculations.

## Key Findings
- Index lookup uses `segment: "index"`, but records persist enum value `"I"`, so
  cache misses and falls back to an unsaved `Instrument`. That object has no
  derivative association, so SENSEX (and even NSE indices if DB is populated via
  importer) yield option picks without security ids, preventing orders.
- Options strike builder accepts the leg even when `security_id` is `nil`. Entry
  guard then calls the placer with a blank `sid`, so the trade aborts before it
  reaches the broker, making the system non self-sufficient for the covered
  indices.
- Risk loop enforces per-trade exits once loss exceeds `entry_price * quantity *
  per_trade_risk_pct`. With config at `0.01` this is effectively a one percent
  move against the option premium (e.g. ₹50 on a ₹5,000 debit), which will fire
  before the intended 30% stop. This disconnect between allocator capital bands
  and realised loss guards causes premature exits and misstates real drawdown
  protection.
- Risk manager only iterates `PositionTracker.active`, so live Dhan positions
  without trackers (e.g. broker-side manual entries or legacy lots from a prior
  run) never hit stop checks. The fetch of `DhanHQ::Models::Position.active`
  only supplies LTP context and cannot add missing trackers, leaving those
  exposures unmanaged.

> **Warning:** Until instrument caching reads the persisted enum values and the
> risk loop keys off account-level loss limits, enable the circuit breaker and
> monitor manual exits for stranded lots.

## Risk Control Map
| Guard | Config Source | Behaviour | Gap |
| --- | --- | --- | --- |
| Hard SL/TP | `config/algo.yml` | Uses entry × (1 ± pct) on tracker lots. | Works, but relies on tracker being present. |
| Per-Trade Loss | `config/algo.yml` | Loss ≥ debit × pct triggers exit. | Too tight versus allocator intent; fires on 1% premium loss. |
| Daily Loss Limit | `config/algo.yml` | Trips circuit breaker via funds API. | Active only when funds endpoint is healthy. |
| Tracker Coverage | N/A | Only trades opened by app have trackers. | Manual or legacy positions stay unmanaged. |

## Recommendations
- Switch the index cache lookup to `segment: "I"` (enum storage) so cached
  instruments load persisted derivatives for both NSE and BSE indices.
- Skip option legs without a derivative match and emit a health alert when
  strike metadata is missing, ensuring orders carry valid security ids.
- Rework per-trade loss checks to reference allocated capital or realised debit
  rather than a one-percent premium move, aligning with allocator risk bands.
- Add a bootstrap sync that creates trackers for any open Dhan positions so the
  risk loop governs every live exposure before placing new trades.
