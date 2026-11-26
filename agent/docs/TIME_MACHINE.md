# Time Machine: historical replay of the live strategy

`src/research/` and `scripts/timemachine.ts` replay the live entry and exit rules over historical sessions, priced
on real option premiums, and then measure how much of the result is evidence and how much is noise. It is a
research tool. It imports no order code, never touches the live risk gate, and no result changes the agent's
behaviour.

```bash
npm run timemachine -- fetch --underlying NIFTY --from 2026-04-01 --to 2026-09-30 --lot-size 75 --dump-raw
npm run timemachine -- run --data data/research/NIFTY-2026-04-01-2026-09-30.json --config config.paper.yml
```

`fetch` makes read-only Dhan calls. `run` needs no credentials and no network.

## Origin: the day-trader-skill pack

The idea comes from `trader-timemachine` in
[Jakeschincariol/day-trader-skill](https://github.com/Jakeschincariol/day-trader-skill) (MIT, Python, US stocks
on Yahoo 5-minute bars). Its source (`trader-timemachine/timemachine.py`) was read before this was written. What it
does:

- It builds a pool of underlying 5-minute bars, each stored as open/high/low/close ratios to the previous close,
  from up to 60 full sessions.
- It builds 10,000 paths by drawing each remaining bar independently (iid) from the same time-of-day slot (±2
  bars), then counts target-first, stop-first and neither. A bar that touches both counts as the stop.
- It re-runs the same rule on the past sessions as a "history" check.

The method does not carry over to buying index options:

| Gap in the original | Consequence for options buying | What this implementation does |
| --- | --- | --- |
| Simulates the underlying, not the premium | A correct direction call can still lose to theta, IV crush and spread | Prices every fill from the held strike's own premium bars |
| iid draws of single bars | Destroys volatility clustering and intraday trend persistence, which are what ORB/SuperTrend trade | No synthetic intraday paths. Resampling is over whole days, in blocks |
| No costs | Index options round trips cost ₹40+ brokerage plus STT, exchange fees and GST, which is material per lot | `roundTripChargesInr` (the live estimate), half-spread on every fill, extra slippage on stops |
| Point estimates only | 33 historical fires give a win-rate CI about ±17 points wide | Wilson intervals on every rate, block-bootstrap interval on mean net R |
| History and simulation share one 60-day window | Nothing is out of sample | Chronological in-sample / out-of-sample split; the verdict requires both |

### The other ten skills against this repository

| Skill | Status here | Action |
| --- | --- | --- |
| `trader-scanner` | Covered: `StrategySession` evaluates five setups per index on closed bars | None. A stock universe scan does not apply to index options |
| `trader-news` | Missing | Candidate: an Indian event-risk calendar (RBI policy, budget, expiry, results of index heavyweights) as an entry block. Not built |
| `trader-entry` | Covered: closed-bar signals, entry window, stale-data gate, serial queue | None |
| `trader-exit` | Covered: `bracketLevels`, trailing stop, time stop, EOD flatten, structure exit | None |
| `trader-risk` | Covered: `evaluatePreTrade`, `DayBook`, broker kill switch | None. The replay calls this gate directly |
| `trader-budget` | Covered: `sizePosition`, whole lots floored to the risk budget | None |
| `trader-broker` | Covered: paper, sandbox and live execution ports, live acknowledgement | None |
| `trader-alerts` | Partly covered: the cockpit and the journal | Optional: push notifications for halts and kill-switch events |
| `trader-analyst` | Not applicable (single-stock earnings) | Skip |
| `trader-pelosi` | Not applicable (US congressional disclosures) | Skip |

## Three methods, three questions

The methods answer different questions, so the report labels each number with the method that produced it.

| Method | Question it answers | What it cannot tell you |
| --- | --- | --- |
| **Historical replay** (`replayDataset`) | What did these exact rules do on these exact days, after costs? | Whether the result was luck. It is one path |
| **Block bootstrap of days** (`bootstrapMeanR`) | How sure can we be that mean net R per trade is above zero, given only these days? | Anything about regimes that are not in the sample |
| **Monte Carlo day paths** (`simulatePaths`) | If the next N days are a reordering of these days, how wide are P&L and drawdown? | The probability of a future profit. It assumes the future looks like the sample |

Both resamplers draw whole days in circular moving blocks, with block length about n^(1/3) days. A day's trades
stay together, and days with no trade are kept, so trade frequency is part of the sample. The seed defaults to
19, and every interval can be reproduced from it.

None of these is a forecast. Ten thousand resamples of a biased sample only reproduce the bias with more
decimal places.

## Fidelity to the live agent

Live code that the replay calls unchanged: `StrategySession.evaluate` (the five active strategies and postures; `prev_day` is research-only and off unless named),
`contextVerdict`/`marketContext`, `structureTurnedAgainst`, `nearestAtmStrike`/`targetEntryStrike`,
`bracketLevels`, `calculateTrailingStop`, `sizePosition`, `evaluatePreTrade` and `roundTripChargesInr`.

| Live behaviour | Replay |
| --- | --- |
| Signal on a closed bar, inside the entry window by the clock | Same, at bar close time |
| LIMIT entry at ask × (1 + `ENTRY_LIMIT_BUFFER_PCT`), cancelled after `ORDER_TIMEOUT_MS` (30 s) | Fill at the next bar's open plus half-spread. Bracket and sizing come from the limit, as in live |
| Stop leg triggers on LTP | Stop when the bar's low ≤ stop. A gap below the stop fills at the open, not at the stop |
| Target leg is a sell limit | Target when the bid (high − half-spread) ≥ target. A gap above fills at the target, not at the better open |
| Bar touches both stop and target | Counted as the stop, and flagged. Over 20% of trades flagged means 5-minute bars are too coarse for the bracket |
| Trailing stop moves on every tick | Moves on the bar high and takes effect from the next bar (never inside the bar that set it) |
| Time stop, `FLATTEN_BY`, structure exit, daily-loss exit | Executed at the next bar's open at the bid |
| Pre-trade gate | `evaluatePreTrade` itself, fed the replay's day book (trade count, cooldown, daily loss, loss at risk, expiry cutoff) |
| Missing premium print for the held strike | The trade is marked `DATA_GAP` and removed from the statistics. Above 5% of trades, the verdict is `INSUFFICIENT_EVIDENCE` |

What is **not** replayed. The report prints this list with every run:

- The chain OI-resistance gate (`CHAIN_ANALYSIS`). There is no historical option chain, so trades it would have
  vetoed are included. From the next session the agent saves one chain per index per bar to
  `data/research/chains/chains-YYYY-MM-DD.jsonl` (about 12 MB a day for three indices); once a few months exist,
  the replay can apply the gate on recorded days.
- The chain-bias vote in the context gate. It is replayed as `NEUTRAL`, which makes the gate stricter, not looser.
- `MAX_SPREAD_PCT`, `MIN_OPEN_INTEREST` and `MIN_VOLUME`. Bars carry no quotes. The default half-spread is
  `MAX_SPREAD_PCT / 2`, the widest spread the live gate accepts, so the default cost model is the worst accepted case.
- Request blocks. Dhan's `toDate` is non-inclusive. Each block of at most 30 sessions is requested with the day after its last session as `toDate`, and `autoAdjustDates` is off. Before 2026-11-10 the final session of each range was not requested, so datasets fetched earlier may lack it. Their windows are Spent, so they describe the market and cannot confirm anything.
- Expiry codes are 0, 1 and 2 (SDK 2.1.0 refuses 3). Expiry choice. The dataset holds one contract per session (`--expiry-flag`, `--expiry-code`). A session whose contract is
  outside `MIN_DAYS_TO_EXPIRY`/`MAX_DAYS_TO_EXPIRY` takes no entry (`EXPIRY_OUT_OF_RANGE`). Where live would pick a later
  expiry instead, the replay cannot. A session with no expiry on record is not limited, and the report says so. BANKNIFTY is
  monthly: fetch it with `--expiry-flag MONTH`, or its sessions get no expiry.
- Concurrent CE and PE positions. The replay holds one position at a time.

## Portfolio replay

`run` replays one index with one position at a time, but live trades several indices from one account. `portfolio
--data A.json,B.json,…` replays each index with no daily limit, then applies the account-wide gates on one
timeline: the shared daily loss limit against realised P&L plus every open stop, `MAX_POSITIONS_PER_SIDE`
(override with `--per-side`) and `MAX_OPEN_POSITIONS`. It is an approximation: a trade the portfolio skips cannot
free its index for a different entry, because the single-index replay never generated one.

On NIFTY, SENSEX and BANKNIFTY 2026-04..09 (paper config, half-spread 0.25%), one position per side gave ₹178k
with a ₹187k day-end drawdown and 5 days losing ₹30k or more, against ₹216k, ₹315k and 9 days at two per side.

## Verdict

| Verdict | Condition |
| --- | --- |
| `INSUFFICIENT_EVIDENCE` | Fewer than 30 priced trades (the same threshold as `report:performance`), fewer than 30 holdout trades, fewer than 30 independent holdout sessions, or more than 5% data-gap trades |
| `NO_TRADE` | The block-bootstrap 95% interval of mean net R, computed on the holdout days only, does not lie above zero; or the holdout mean net R ≤ 0; the holdout mean without its single best session is not above zero, or that session supplies more than the derived cap of positive net R; or the verdict fails a cost stress |
| `EDGE_SUPPORTED` | Holds on the holdout, survives removing its single best session, stays within the profit-share cap derived from its winning sessions (`docs/research/DOMINANCE.md`), and holds under both cost stresses: 1% half-spread, and twice the stop slippage |

The holdout is the chronologically later part of the sample (`splitFraction`, 0.6 by default). The whole sample never
decides a verdict. A whole-sample interval lets the earlier days carry the result. Cost stress can only downgrade:
a stressed run that is not `EDGE_SUPPORTED` makes the verdict `NO_TRADE`, and no stress run can upgrade a weaker one.
Rule version `holdout-v3` is recorded on every `runs.jsonl` line and in every ledger record. `holdout-v1` used 20 holdout sessions with no best-session test. `holdout-v2` had no profit-share cap and used the holiday-shift expiry. None of the three are comparable to v3.

`EDGE_SUPPORTED` means only that this sample does not contradict a positive expectancy after modelled costs. It
does not authorise live trading. Every parameter sweep is another test on the same days: if you try k
configurations and keep the best, its interval is optimistic by roughly a factor of k. Judge a chosen setting on
days that were not used to choose it. Every `run` appends its dataset, config fingerprint, cost model, trade
count, mean net R and verdict to `data/research/runs.jsonl`, so the number of variants tried on a dataset (the k
above) can be counted.

## Data source: Dhan `/charts/rollingoption`

`client.expiredOptionsData.fetch` in `@nemesis-oss/dhanhq-sdk` 2.0.1 posts to `/charts/rollingoption`. The response
layout below was written against the 1.3.0-era SDK. SDK 2.1.0 documents the same `data.ce` / `data.pe` parallel arrays with
numeric timestamps, which the parser accepts, but 2.1.0 is not on npm yet, so that is read from its source, not run. The
layout is re-verified on the pinned SDK by OTA-314, and no recording exists yet.
Facts verified from the SDK source:

- Strikes are **relative to ATM at each bar** (`ATM`, `ATM+1`, `ATM-2`, …). The request takes the underlying's
  security id, not a contract's. One series is therefore not one contract. `fetch` pulls ATM±`--offsets` and
  `pivotByStrike` re-keys every bar by the `strike` column, which rebuilds each fixed contract's series. A held
  strike that drifts beyond the fetched band leaves its series, and the trade becomes `DATA_GAP`.
- The SDK validates `expiryCode` 1–10, `interval` 1/5/15/25/60, and a range of at most 180 days.
  `fetch` uses 30-day windows.
- The SDK passes the response body through **untyped**. Its declared type (`data?: ExpiredOptionsDataPoint[]`)
  is not what the parser expects. `parseRollingOptionResponse` accepts only the column layout
  `{ data: { ce | pe: { open, high, low, close, strike, timestamp, volume? } } }` and refuses anything else with
  the keys it found.

### Implied volatility and open interest

`fetch` also requests `iv` and `oi`. A live account returned both columns, plus `spot`, on 2026-10-26, and
served 1-minute bars as well as 5-minute ones. They are stored per option bar as optional fields, so older
datasets without them still load. IV is the source's annualised implied volatility in percent.

An exit on falling IV (leave once the held strike's IV is 1.5–3 vol points below entry) was tested on
NIFTY 2025-10..2026-09, SENSEX and BANKNIFTY 2026-04..09 and changed mean net R by under 0.02 either way, so
it was removed. `fetch --interval 1` pulls 1-minute bars; `run` needs `BAR_MINUTES` to match the dataset.

### Defect: 5-minute rolling bars mix two strikes (found 2026-11-03)

A rolling series is "ATM+k", re-centred every bar. When spot crosses a strike boundary inside a 5-minute bar, that
bar's high and low come from two different contracts, and `pivotByStrike` files the mixed bar under one strike.
Closes are unaffected. Measured on NIFTY 2026-04..09, the 5-minute fetch against the 1-minute fetch of the same days
rebuilt as 5-minute bars:

| | Bars | Bar high or low differs | Close differs |
| --- | --- | --- | --- |
| ATM unchanged inside the bar | 287,452 | 0.9% | 0.0% |
| ATM changed inside the bar | 98,108 | 94.9% | 0.0% |

On those bars the near-ATM call's range is twice what delta implies (31.3 against 0.5 × spot range = 14.5; the
1-minute rebuild gives 15.1). Every 5-minute file shows it: the ATM call's range over 0.5 × spot range is 1.7–2.2 on
bars that cross a strike boundary and 1.1 on bars that do not (NIFTY 2025H2, NIFTY 2026H1, BANKNIFTY and SENSEX
2026H1). The 1-minute file reads 1.07 on both.

The fake highs and lows trigger stops and targets that never traded. On NIFTY 2026H1 with `config.paper.yml`:

| | Trades | Mean net R | Profit factor | Target first | Gap-through stops |
| --- | --- | --- | --- | --- | --- |
| 5-minute file | 553 | −0.017 | 0.87 | 12.7% | 25 |
| 1-minute fetch rebuilt as 5-minute | 549 | −0.058 | 0.65 | 5.8% | 1 |

**Use 1-minute fetches.** `run`, `portfolio` and `trail-study` rebuild 5-minute bars from a 1-minute dataset
automatically (`atBarMinutes`). Earlier 5-minute verdicts were too generous, and none should be quoted until rerun on
1-minute data. A 1-minute bar can still mix strikes when spot crosses a boundary within the minute, but far less often
and over a smaller range.

The NIFTY 2026H1 5-minute file also carries lot size 75 where the 1-minute file of the same months carries 65.

## Verification required before trusting a dataset

These items cannot be verified from this environment (no broker credentials):

1. **Response layout.** Run `fetch` once with `--dump-raw` on a short range and check `<out>.raw-CE.json` against
   the layout above. A mismatch fails the fetch rather than producing a wrong dataset.
2. **Timestamp convention.** Option bars are converted with `DHAN_EPOCH_IST_SHIFTED`, the same switch as spot.
   `parseDataset` refuses bars outside 09:15–15:30 IST, which catches a 5h30m error but not a smaller one.
3. **Offset band.** How many ATM offsets Dhan serves for each index and expiry type. Lower `--offsets` if
   requests fail. A large `DATA_GAP` count means the band is too narrow for the moves in the range.
4. **Expiry code at the roll.** Checked for NIFTY weekly on July 2026 1-minute data: on each Tuesday the ATM
   straddle at 15:20 was ₹3–13 against ₹120–365 on other days, so `expiryCode 1` on expiry day is that day's
   expiry and expiry-day theta is in the sample. BSE agrees: on SENSEX 2026-04..09 5-minute data the median
   15:20 ATM straddle was ₹60 on Thursdays (expiry) against ₹510–970 on other weekdays; the few high Thursdays
   pair with low Wednesdays, consistent with holiday-shifted expiries. BANKNIFTY (monthly) not yet checked: its rule, the last Tuesday of the month, comes from broker notices of the NSE
   2025 revision, not from Dhan data.
5. **Expiry dates.** The rolling source does not return them. Each session takes its nominal expiry, the next expiry weekday on or after its date, from its own date alone. An exchange holiday on the expiry weekday is not modelled, so the session before it is NEAR rather than EXPIRY. The earlier holiday-shift rule read later sessions, which is look-ahead, and was removed.
6. **Lot size.** It is given per fetch (`--lot-size`). Split a fetch at every exchange lot-size revision.

## Context cells (`run --cells`)

`run --cells [--vix data/research/INDIAVIX-….json]` splits each strategy's priced trades by one context dimension
at a time (regime, day-trend alignment, time bucket, expiry day, optional VIX tercile from each day's opening VIX, ranked against the trailing 252 sessions and tagged only after 60 of them).
`--vix` was ranked against every date in the dataset until 2026-11-13, which used later days. Cell reports printed before that change are
not valid evidence. No ledger record cites a `--vix` run (checked 2026-11-13).

`--iv` adds the entry's implied-volatility bucket. The ATM IV at the signal bar is ranked, mid-rank with ties at half weight,
against the ATM IV of the 20 prior sessions at the same minute: `LOW` below a third, `HIGH` from two thirds, `MID` between.
`UNKNOWN` when fewer than 10 prior observations exist or the bars carry no IV. The constants are in
`src/research/ivContext.ts` and pinned by `tests/ivContext.test.ts`. The bucket never changes a trade. The cut is discovery
only: a pattern suggests a hypothesis, which then needs a pre-registration and a frozen window nobody has looked at.
Each run's ledger record also carries the signal count and the rejections by reason (`signals`, `rejections`). Accounting: a run records one variant in the ledger, with its cell count in `cells`. The divisor for a run is its cells times
the records so far, so the cells of earlier runs are not in it. Changing that is a rule change, reviewed on its own.
A cell is `EDGE_SUPPORTED` only when P(mean net R ≤ 0), on its holdout days, is below 0.025 ÷ (cells × variants evaluated
across the research program), its holdout mean is positive, and it holds under both cost stresses. Fewer than 30 holdout
trades or fewer than 30 holdout sessions is `INSUFFICIENT_EVIDENCE`. The variant count is every record in the research ledger, `docs/research/experiments.jsonl` (OTA-313, OTA-315).

Hold-out discipline: choose candidate cells on one period, then confirm them once on a later period that played no
part in the choice. First pass (2026-11-02): NIFTY 2025H, 60 cells, none passed. The two best,
`trend | trendAlignment=WITH` (P 0.0145) and `trend | regime=TRENDING` (P 0.019), were checked once on NIFTY 2026H:
mean net R −0.020 and −0.040, `NO_TRADE`. No cell is promoted.
