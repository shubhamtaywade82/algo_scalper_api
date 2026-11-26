# Holdout ledger

Every period the research has touched, and what it was used for. A period is `Spent` once it has informed any decision:
a choice of family, cell, threshold, exit rule or parameter. A `Spent` period can still describe the market; it cannot
confirm a hypothesis. A period is `Frozen` when a dataset manifest for it is committed here and no decision has used it.
Only a `Frozen` window can confirm a pre-registered hypothesis (`PREREG.md`).

## Windows

The labels below are copied from `docs/TIME_MACHINE.md` and `docs/ROADMAP.md`. They are not consistent with one another
(for example "2025H" and "2025H2–2026H1" use different half-year conventions), and the dataset files that fix the exact
dates are in `data/`, which is not in the repository. Each window must be restated with exact `from`/`to` dates from its
manifest before it is used for anything. Until then, every label here is `Spent`.

| Window (as labelled) | Underlyings | Used for | Status |
| --- | --- | --- | --- |
| NIFTY 2025H | NIFTY | First context-cell pass, 60 cells: discovery of the two best cells. The 0.25% half-spread EDGE_SUPPORTED verdict and the 1% NO_TRADE verdict | Spent (discovery) |
| NIFTY 2026H | NIFTY | Confirmation of the two best 2025H cells, checked once: mean net R −0.020 and −0.040 | Spent (confirmation) |
| NIFTY 2025-10..2026-09 | NIFTY | Exit sweeps (stop %, R target, time stop) and the IV-crush exit test. Contains NIFTY 2026H | Spent (confirmation) |
| SENSEX and BANKNIFTY 2026-04..09 | SENSEX, BANKNIFTY | Exit sweeps and the IV-crush exit test | Spent (confirmation) |
| 2025H2–2026H1 | NIFTY, BANKNIFTY, SENSEX | The ~550-trades-per-underlying counts and the mean net R range in `ROADMAP.md` fact 1 | Spent (description) |
| 2026-10-01..2026-12-31 | NIFTY, BANKNIFTY, SENSEX | One raw-response layout check on 2026-10-26, which is not a P&L decision. Otherwise untouched. Reserved on 2026-11-10 for the three hypotheses under "Reserved window" below. NIFTY 2026-10-01..11-12 was looked at by the workbench VIX lab (entry 2026-11-13) | Not frozen. NIFTY 2026-10-01..11-12 Spent. BANKNIFTY and SENSEX exposed (see the 2026-11-13 disposition). The reserved hypotheses cannot confirm here as written. OTA-314 freezes what remains after the window closes |
| 2026-04-01..2026-11-12 | NIFTY | Workbench lab, outside this repository: a VIX-percentile band split of a buy-at-09:30 ATM CE/PE replay (153 days), and the choice of the next experiments (ORB, then VWAP) | Spent (discovery, and the choice of next step). Overlaps the reserved window for 2026-10-01..11-12 |
| 2027-01-01 onward | NIFTY, BANKNIFTY, SENSEX | Untouched | Not yet Frozen |

## Holdout disposition (2026-11-13)

Proposed by the reviewer on 2026-11-13. The operator has not accepted it yet. The open questions below are the operator's to answer.

**Terms.**
- **Spent:** its results or statistics informed a decision (a choice of family, cell, threshold, exit, parameter or next experiment). It can describe the market and support debugging. It cannot confirm a hypothesis.
- **Exposed:** the repo or the operator's records show an inspection of outcomes or data that may have informed a decision, and its extent is not established. Not usable as a holdout until cleared.
- **Unusable:** data that fails a quality check for the stated purpose, for example a layout not verified against the pinned SDK. Separate from spent: unusable data can also be spent.
- **Candidate:** a window not yet frozen. It becomes usable only after freezing (`PREREG.md`, rule 2).

**Dispositions.**

| Dataset | Disposition | Usable for | Basis |
| --- | --- | --- | --- |
| NIFTY 2026-04-01 to 11-12, all of it | Spent | Discovery, debugging, description. Not confirmation | The VIX-percentile replay (2026-11-13) rejected the low-VIX filter for the blind 09:30 baseline and prioritised the ORB and VWAP entries. The whole range is spent for those decisions, not only the October–November overlap |
| NIFTY 2026-10-01 to 11-12, reserved | Spent | As above | Same |
| BANKNIFTY 2026-10-01 to 11-12, reserved | Exposed. Not preserved on current evidence | Discovery and debugging only, until cleared | Pooled paper P&L of 2026-10-26 set `max_daily_loss_pct` and the daily-loss brake (`config.paper.yml`; `be2c4fd`). The paper profile lists this instrument, so it may have traded that day. Data-quality check of live chain fields on 2026-10-27 (`README.md`). The 2026-10-27 expiry commit (`8a459b2`) says BANKNIFTY expiry data is not verified |
| SENSEX 2026-10-01 to 11-12, reserved | Exposed. Not preserved on current evidence | As above | Same pooled 2026-10-26 P&L. Chain-field check on 2026-10-27 |
| All instruments from 2026-11-13 | Candidate fresh holdout, pooled | Confirmation, once frozen | Not inspected. Start and end to be fixed before any session is viewed |

NIFTY history is spent for confirmation but stays useful for discovery, debugging and description. BANKNIFTY and SENSEX cannot be called clean on the repo's evidence, so the earlier "conditionally preserved" status is replaced by "exposed".

**Influence record.** Events from 2026-10-26 that changed a parameter, a control or a dataset, or inspected data.

| Date | Event | Data | Decision or inspection | Status |
| --- | --- | --- | --- | --- |
| 2026-10-26 | Paper day: a +₹11.8k peak became −₹67k with no daily-loss brake | Pooled over the underlyings the paper profile trades | `max_daily_loss_pct` set to 4.0 (`config.paper.yml`) | Outcome exposure. Which underlyings traded that day is pending |
| 2026-10-26 | Exit parameters: stop 30% to 50%, target 1.5R to 1.0R, max hold 90 to 30 minutes (`64393fe`) | Cites replay datasets 2025-10 to 2026-09, and "noise" in trades | Parameter change | Replay part: Spent. Paper-trade part: pending |
| 2026-10-26 | Intraday history zero-volume bar after the close, 18:40 IST (`11f91ad`) | Instrument not recorded | Data-quality fix | Data-quality exposure. Instrument pending |
| 2026-10-26 | `max_days_to_expiry` 4 to 6, because NIFTY and SENSEX had no contract on some weekdays (`11f91ad`) | Contract availability, NIFTY and SENSEX | Parameter change | Data-availability exposure |
| 2026-10-26 | Raw response layout check with `iv`, `oi` and `spot` (`docs/TIME_MACHINE.md`) | Instrument not recorded | Layout check, not P&L | Data-quality exposure. Instrument pending |
| 2026-10-26 to 27 | Epoch convention verified against live bars (`README.md`) | Instrument not recorded | Data-quality check | Data-quality exposure. Instrument pending |
| 2026-10-26 | IV-crush exit removed (`24191d3`) | NIFTY 2025-10 to 2026-09; SENSEX and BANKNIFTY 2026-04 to 09 | Removal | Spent. No October 2026 data cited |
| 2026-10-27 | Cross-index position limit per side (`b99728e`) | Motivation not recorded | Risk limit | Pending: did October results motivate it? |
| 2026-10-27 | Session drawdown reset and daily-loss brake toggle (`be2c4fd`) | The 2026-10-26 "no brake" event (config comment) | Risk control | Outcome exposure, 2026-10-26 |
| 2026-10-27 | Chain recording starts; alerts added (`45213a0`) | Future snapshots for the recorded underlyings (scope not checked here) | Recording, not inspection | Snapshots exist in the window. Any use of them for decisions is an inspection |
| 2026-10-27 | SENSEX expiry-day observations; BANKNIFTY "not yet verified" (`8a459b2`) | SENSEX 2026-04 to 09 (Spent). BANKNIFTY: none recorded | Documentation | SENSEX spent. BANKNIFTY none recorded |
| 2026-10-27 | Chain fields checked with `smoke:live` on NIFTY, BANKNIFTY and SENSEX (`README.md`) | Live chain snapshots, 2026-10-27 | Data-quality check | Data-quality exposure, all three instruments |
| 2026-10-27 | `MAX_RISK_PER_TRADE_PCT=30` found in the environment (`src/config.ts`, `CLAUDE.md`) | Configuration | Configuration correction | Operational. Confirm no P&L was viewed |
| 2026-11-03 | 1-minute rolling-option requests refused, HTTP 400 (`scripts/timemachine.ts`) | Window and instrument not recorded | Fetch behaviour | Pending |
| 2026-11-03 | 5-minute strike-mixing defect analysed (`ff5ed32`) | NIFTY 2026-04 to 09 and 2026H1 | Data fix | Spent |
| 2026-11-03 | Ledger backfills of documented evidence | 2025H, 2026H and September 2026 datasets | Ledger records | None on October–November |
| 2026-11-13 | VIX-percentile replay, outside this repo | NIFTY 2026-04-01 to 11-12 | Rejected the low-VIX filter for the blind baseline; prioritised ORB and VWAP | Spent |

**Open questions for the operator.**
1. Which underlyings traded in the paper profile on 2026-10-26 and 2026-10-27?
2. Did any review of October–November results inform a decision, including the cross-index limit (`b99728e`) and the exit change (`64393fe`)?
3. Which instrument did the 2026-10-26 layout check, the 18:40 history bar and the epoch check use? Which window did the 2026-11-03 request target?
4. Were any dashboards, notebooks or reports for October–November BANKNIFTY or SENSEX viewed?
5. Accept the disposition: NIFTY spent; BANKNIFTY and SENSEX exposed, not preserved unless cleared; a new pooled candidate?
6. The end date of the candidate window.

**Candidate pooled holdout (proposed).**
- Instruments: NIFTY, BANKNIFTY and SENSEX.
- Start: the first session whose results nobody has viewed. Today is Friday 2026-11-13. If that session has been viewed, the window starts Monday 2026-11-16.
- End: fixed by the operator before any session in the window is viewed.
- Hypothesis: to be written and committed to `PREREG.md` before the window is viewed. Not yet written.
- Monitoring: operational monitoring (halts, kill switch, feed health, errors) is allowed. Reviewing P&L or results to choose or change a strategy, parameter, limit, selection or capital decision is a look. It spends the window and must be logged.
- Freeze: at the end, the manifest records the dataset `sha256` and `sdkVersion`, as OTA-314 requires.
- Draft specification: `docs/research/PREREG.md`, "Candidate specification (not registered)", CAND-2026-11-13-1. Its OPEN items are the operator's to settle before freeze.

**Instrument-specific candidate (BANKNIFTY and SENSEX).** It has no clean period of its own. Its only clean period is the candidate window above, so it is a subset of the pooled candidate. It uses the same observations, so it is not an independent confirmation, and both are counted in the divisor. It can start earlier only if the operator clears the exposures above.

**Original reserved hypotheses, preserved as written.** The text of 2026-11-10 says "pooled" and "one hypothesis each for NIFTY, SENSEX and BANKNIFTY". The reading recorded here is three per-instrument hypotheses on one rule. "Pooled" describes the strategy set. If a single cross-instrument test was meant, it is a different hypothesis and must be registered as new. None is registered. NIFTY cannot confirm on this window. BANKNIFTY and SENSEX cannot confirm on current evidence. The hypotheses are not withdrawn. Any reuse on the candidate window is a new registration.

**Overlap rule.** Hypotheses that share observations are not independent confirmations. Each is counted in the divisor.

**Requirements for any lab output that informs a decision** (VIX replay, ORB and VWAP):
- Keep CE and PE paired within each session.
- Use whole-day bootstrap resampling, with a contiguous multi-session block bootstrap as sensitivity.
- State the confidence level and the interval method.
- Correct for multiple comparisons (three bands by two sides), or label the result exploratory.
- Report by expiry and by DTE.
- Compare realised underlying movement with the contemporaneous ATM straddle-implied move.

Until these hold, lab results are exploratory and cannot justify a decision.

**P1 definition (discovery specification, not registered).** P1-A reproduces `openingRangeCross` (`src/strategy/orbSupertrend.ts`) with the paper profile's bar size, `bar_minutes: 5`. This replaces the 1-minute specification of 2026-11-13.
- Opening range: bars keyed 09:15, 09:20 and 09:25. A missing bar means no range that day (`sessionRange`).
- Signal bar: keyed at or after 09:30, inside the entry window [09:15, 14:00), with the previous bar on the same date. In practice the signal window starts at 09:30.
- Bullish: close above the range high, and previous close at or below it. Bearish: close below the range low, and previous close at or above it. A bar already beyond the level does not fire.
- Entry: the next bar's open. Strike: ATM at the signal close, offset zero.
- P1-B adds one condition: CE needs the signal close above session VWAP, and PE below it. VWAP needs volume. Missing volume is unavailable, not zero. If it is unavailable, P1-B is not run.
- Control: buy ATM CE and PE at the open of the 09:30 bar.
- Exits, costs and contract selection are identical across control, P1-A and P1-B. The lab's exits are a control choice, not an endorsement. A second exit set is a separate experiment.
- The bot's replay allows repeated trades (`maxTradesPerDay` 0 is unlimited, and the cooldown is 900 seconds). The review's "one entry per session" is a different rule. Choose it, and label it.

## Entries

| Date | Window | Action | Who |
| --- | --- | --- | --- |
| 2026-11-02 | NIFTY 2025H | Discovery pass, 60 cells | research |
| 2026-11-02 | NIFTY 2026H | Single confirmation of the two best cells | research |
| 2026-11-03 | all windows above | Recorded in this file. Exit-sweep and IV-crush windows marked as overlapping NIFTY 2026H | research |
| 2026-11-10 | 2026-10-01..2026-12-31 | End date fixed and the window reserved for three pooled paper-profile hypotheses (NIFTY, SENSEX, BANKNIFTY). Nothing was fetched or run | operator |
| 2026-11-03 | ledger | The documented evidence written to `docs/research/experiments.jsonl` as backfills, once each, with citations | research |
| 2026-11-13 | NIFTY 2026-04-01..2026-11-12 | Workbench VIX-percentile lab run, reported 2026-11-13. Its result chose the next experiment. It looked at 2026-10-01..11-12 of the reserved window before the freeze, which the reserved-window rule forbids. The lab's runs are not in `experiments.jsonl`; they must be imported before they count toward the divisor | operator, outside this repository |
| 2026-11-13 | Holdout disposition | Recorded in the section "Holdout disposition (2026-11-13)": NIFTY spent; BANKNIFTY and SENSEX exposed; a candidate pooled holdout from 2026-11-13 (2026-11-16 if 13 November is viewed). The operator's acceptance is pending. No replay run for the disposition | reviewer (proposal); operator (acceptance pending) |

## Reserved window

Decided by the operator on 2026-11-10, before any data in the window was fetched.

- **Window.** 2026-10-01 to 2026-12-31. The end date is fixed now so that it cannot be chosen after seeing results. On
  2026-11-10 the window held fewer than the 30 sessions the holdout floor needs, so no run on it was possible.
- **Hypotheses.** The strategy set of `config.paper.yml`, pooled, has a holdout block-bootstrap 95% lower bound of mean
  net R above zero after costs, under the OTA-308 rules. One hypothesis each for NIFTY, SENSEX and BANKNIFTY (the third
  added on 2026-11-10, the same day, before any fetch). The profile is the
  one at the commit named in the `PREREG.md` entry, and it is not changed between now and the run.
- **BANKNIFTY limits, known before the run.** BANKNIFTY options are monthly. On 2026-11-10, before any fetch, the replay
  gained a monthly expiry rule (the last Tuesday of the month) and began to apply `MIN_DAYS_TO_EXPIRY` and
  `MAX_DAYS_TO_EXPIRY`, so it now trades only the sessions the paper profile can trade. Two limits remain. The rule comes
  from broker notices and is not checked against Dhan data, and a holiday on the expiry Tuesday is not modelled. With the
  profile's six-day limit, BANKNIFTY can enter on about five sessions a month, so this window may fall short of the
  30-trade floor. A short sample is reported as insufficient evidence, not as a pass or a fail, and it still counts as
  one variant in the divisor. The dataset must be fetched with `--expiry-flag MONTH`.
- **Implied-volatility cut.** `run --cells --iv` is also a look at this window. Do not run it on this window before the freeze.
- **Split fraction, open.** The Time Machine judges only the later part of a dataset: at its default `--split 0.6`, the
  last 40% of sessions. A window of about 60 sessions then has about 24 holdout sessions, below the floor of 30. The
  split fraction must be written in the `PREREG.md` entries before the run, and it is not decided yet.
- **Not a registration.** `PREREG.md` rule 2 needs a Frozen window first. This section records the choice and its date.
  The entries are committed to `PREREG.md` after the freeze, with the same hypotheses.
- **Fetch date.** The fetch reads expired contracts only, so it runs after the last weekly expiry that the window's final
  sessions traded has passed.
- **No look before the freeze.** No replay, cell pass or description is run on any part of this window before the run in
  step 3 below. A look of any kind makes the window `Spent`.
- **Breach recorded 2026-11-13.** The workbench VIX-percentile lab was run on NIFTY from 2026-04-01 to 2026-11-12, which includes
  2026-10-01 to 2026-11-12 of this window. NIFTY is Spent for that part, so a NIFTY hypothesis cannot be confirmed on this window.
  The pooled hypothesis includes NIFTY, so as registered it cannot be confirmed here either. Re-scoping is the operator's decision,
  and it must be written in `PREREG.md` before anything is registered. BANKNIFTY and SENSEX appear in no entry of this register.
  The operator must state whether anything else has looked at October and November, including the paper journal, before the freeze.

- **Disposition (2026-11-13).** NIFTY is spent for this window. BANKNIFTY and SENSEX are exposed on the repo's evidence. The reserved hypotheses cannot confirm here as written. Details are in the section "Holdout disposition (2026-11-13)".

## What must happen before the next confirmatory run

1. OTA-314: after the reserved window closes, fetch it from 2026-10-01 to 2026-12-31, check its layout against the pinned SDK (2.0.1 until the bump to 2.1.0 is published, then 2.1.0), record its
   `sha256` and `sdkVersion` in its manifest, and change its status to `Frozen` here, with the date.
2. Register the hypothesis in `PREREG.md`, commit it, and register it in the ledger with `npm run ledger -- register`, before the run.
3. Run once. The run appends its record to the ledger. Record the result in `PREREG.md` with its ledger sequence number.

## Preserved evidence

The 2026H results are kept permanently as historical research evidence. They are not deleted, and they are not relabelled
as an untouched holdout.

- **NIFTY 2026H, confirmation of the two best 2025H cells (2026-11-02).** Mean net R −0.020 and −0.040, both NO_TRADE.
  This window was already spent when it was checked: the exit-rule sweeps and the IV-crush test had run on NIFTY
  2025-10..2026-09, which contains it. The result stands as the record of what happened, and stays `Spent`.
- The ledger holds it as `doc:TIME_MACHINE.md:confirmation-2026H-spent`, a backfill with `holdout_status: Spent`, linked to
  the overlap group of the exit sweep that covered it (`docs/research/experiments.jsonl`). `scripts/ledger.ts verify` and the
  committed-ledger tests fail if it is removed, edited, or relabelled `Frozen`.
- A new confirmation on NIFTY 2026H is not possible. A confirmation needs a Frozen window, and no such window exists in the
  repository's data. The next confirmation runs on a window frozen after the fresh data is fetched (OTA-314).
