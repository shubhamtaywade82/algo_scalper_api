# Pre-registration

A hypothesis is tested once, on a window nobody has used for it, under rules fixed before the run. This file is the record.
An entry is committed to git before the run it describes, so the commit date is the evidence.

## Rules

1. **One entry per hypothesis.** A parameter change is a new hypothesis. A rerun with the same rules on the same window is
   not a new test: it is the same test again, and its result stands.
2. **The window must be `Frozen` in `HOLDOUT.md`** before the entry is committed. A window that has been used for any
   decision is `Spent` and cannot confirm anything.
3. **Thresholds are written before the run.** Minimum trades (30), minimum independent sessions (30), the best-session test, the derived profit-share cap, the
   holdout interval rule, and the cost stress (1% half-spread and 2× stop slippage) apply as written in `docs/ROADMAP.md`
   (OTA-308). An entry that changes them must say so, and the change is reviewed as a rule change.
4. **A failed hypothesis is recorded as failed.** It stays in the research ledger (`docs/research/experiments.jsonl`) and counts in the
   multiple-testing divisor (OTA-313, OTA-315). It is not replaced by a tweak on the same window. The next hypothesis is registered as a new entry.
5. **Discovery is not confirmation.** A pattern found while looking at a window is a hypothesis for a later, frozen
   window. It cannot be confirmed on the window that suggested it.
6. **Registration is recorded in the ledger.** Before a confirmation runs, `npm run ledger -- register --hypothesis <id>` writes a registration to `docs/research/experiments.jsonl`. The ledger refuses a confirmation without one, and refuses a confirmation on a window that is not Frozen.

## Entry template

```
### PRE-<yyyy-mm-dd>-<n>: <one-line hypothesis>
- Committed: <git commit that adds this entry>
- Family and cells: <strategy family> | <context dimension=value, or "pooled">
- Underlyings: <NIFTY | BANKNIFTY | SENSEX, pooled only if the rule is the same across them>
- Window: <a window from HOLDOUT.md with status Frozen>
- Dataset sha256 and sdkVersion: <from the frozen manifest>
- Metric and rule: <e.g. holdout block-bootstrap 95% lower bound of mean net R > 0, rules as in OTA-308>
- Minimum holdout trades and sessions: 30 and 30, with the best-session test, the derived profit-share cap and the five-session block floor. These are eligibility floors, not statistical significance (unless changed here, with the reason)
- Cost stress: 1% half-spread and 2× stop slippage, both must pass
- Variants counted in the divisor at registration: <value of priorVariantCount>
- Result: <pending | PASS | FAIL, with the ledger sequence number>
```

## Registered hypotheses

None registered. Preserved and candidate hypotheses are described in `docs/research/HOLDOUT.md`, section "Holdout disposition (2026-11-13)". A candidate becomes an entry here only after its window is frozen.

## Candidate specification: pooled paper-profile confirmation (not registered)

**Status.** A candidate, identified CAND-2026-11-13-1. It is not an entry under rule 2 and nothing here is registered. The entry is committed at freeze, after the candidate window closes and before any replay of it, and it must match this text or amend it with a dated note. Items marked OPEN are the operator's to settle before freeze. Each resolution is recorded here by a dated commit. When registered, the entry takes a PRE-<date>-<n> ID.

### Hypothesis

The configured strategy set of `config.paper.yml` at commit 68df22f (posture `scout`; range, trend, ema_cross, momentum and continuation), replayed on NIFTY, BANKNIFTY and SENSEX over the candidate window under the profile's contract, sizing, limit and exit rules, has positive mean net R per taken trade after costs, pooled over the three instruments. Its 95% day-block lower bound is above zero, and every guard below passes.

The evidence so far gives no reason to expect a pass. Earlier replays of this strategy set, under earlier exit settings (changed on 2026-10-26), had mean net R between −0.004 and +0.046 (ROADMAP fact 1, on earlier data). NO_TRADE is a legitimate result. This test is not designed to find an edge.

### Scope

- Replayed configuration only. The run's divergences are part of the record: the chain OI-resistance gate is not replayed, MAX_SPREAD_PCT, MIN_OPEN_INTEREST and MIN_VOLUME are not replayed, and the context gate's chain-bias vote is replayed as NEUTRAL. The claim covers the replayed set, not the live gates. OPEN: implement the chain gate on recorded chain snapshots before freeze (the ChainRecorder has recorded since 2026-10-27), or accept this scope.
- Expiry days are included, as configured.
- No environment overrides. The run's `configFingerprint` must equal the reference value, computed from `config.paper.yml` with defaults only: `7e37721cd8c0a3a2aa0b9e0d0b78bc82d4179be6024bc777d2d57c23a66c21c7`.
- Not a trading authorisation. The live risk gate is unchanged by any result.

### Data

- Instruments: NIFTY, BANKNIFTY and SENSEX.
- Window start: OPEN. The first session no one has viewed. Default 2026-11-16, unless the operator attests that 2026-11-13 was not viewed.
- Window end: OPEN. Recommended: the 60th trading session by the NSE calendar, written as a date before any session in the window is viewed. The repo holds no calendar, so the operator counts it. Sixty sessions give twelve blocks of five.
- Holdout: the whole window. A confirmation window has no development part, so the 60/40 split used for development datasets is not applied. The OTA-308 floors apply to the whole window.
- Source: Time Machine datasets fetched after the window closes. Interval 5 minutes (`BAR_MINUTES` 5). Expiry code 1, the nearest contract. NIFTY and SENSEX use `--expiry-flag WEEK`, and BANKNIFTY uses `--expiry-flag MONTH`. Lot size per session comes from the scrip master, and the fetch is split at each change. ATM offsets use the fetch default (±10).
- Warm-up: no pre-window data is fetched. The first window sessions use in-window history only. This is a declared divergence from live, where warm-up is five sessions of history. OPEN: allowing pre-window inputs, which would touch spent or exposed sessions as inputs only. Recommended: none.
- Missing data: a session with missing spot bars is replayed as recorded. No session is removed afterwards. Counts are reported.
- Dataset sha256 and sdkVersion: recorded per instrument at freeze.

### Metric and rule

Primary metric: mean net R per taken trade, pooled. R is net P&L divided by planned risk at the stop, as the replay defines it.

Pooling: the three instruments are replayed without daily caps. The profile's shared limits are then applied in time order, as `timemachine portfolio` does: a daily loss limit of capital × `max_daily_loss_pct` (₹40,000 on ₹10 lakh at 4%), one position per side, and six open positions.

Interval: day-block bootstrap. A unit is a session, holding every taken trade of that session across the three instruments. Sessions with no trade count as units. 10,000 resamples, seed 19. Block length is max(5, round(cbrt(sessions))), which is 5 for windows up to 166 sessions. The lower bound is the 2.5th percentile of the resampled means.

### Guards and cost stresses (fixed)

EDGE_SUPPORTED requires all of the following.
1. At least 30 taken trades pooled, and at least 30 sessions.
2. At most 5% of replayed trades hit a missing premium bar.
3. The lower bound of the 95% interval is above zero.
4. Mean net R over the window is above zero.
5. Mean net R with the single best session removed is above zero.
6. Dominance: the best session's share of positive net R is at most the cap from `dominanceCap` with seed 19 (`DOMINANCE.md`, as implemented, not retuned).
7. Both cost stresses hold, each re-running rules 1 to 6. S1: half-spread and stop slippage each at least 1%. S2: stop slippage twice base.

Base costs are set explicitly and recorded in the costs fingerprint: half-spread 0.25% and stop slippage 0.25%. The defaults are not used. `adverseCostsFor` sets both to MAX_SPREAD_PCT / 2, which is 1%, and that makes S1 identical to the base. The 0.25% base is an assumption, because spreads are not measured in our data. Charges are the replay's statutory charges.

Warnings, reported and not decisive: more than 20% of trades touch both stop and target in one bar (counted as stops), and sessions without an expiry.

Mapping: EDGE_SUPPORTED is confirmed. NO_TRADE is rejected and recorded as a failed hypothesis under rule 4. INSUFFICIENT_EVIDENCE is inconclusive, with no claim either way, and needs a new window.

### Multiplicity and registration

- The pooled test is one variant. The base run and the two stresses belong to this entry. No other run may use this window: no cells, sweeps, alternative parameters or outcome charts.
- The divisor is read from `npm run ledger -- verify` at the registration commit. The program ledger currently holds 4 records and 4 variants. Lab runs over the same data must be imported first (`ledger -- import --runs <path>`), or the divisor is understated.
- The register command takes one underlying, so the pooled record needs `--underlying POOLED`. OPEN: the overlap rule keys on one underlying, so the pooled record needs an overlap group declared explicitly, which keeps it from counting as independent of the instrument-specific candidate in `HOLDOUT.md`.
- The instrument-specific candidate shares these observations, so it is not an independent confirmation.

### Preconditions before freeze

1. A pooled verdict: the portfolio trades, the day-block bootstrap across instruments, rules 1 to 7, and the whole window as holdout. Not yet written. It must be tested and committed before the window opens, and it changes no data.
2. BANKNIFTY's monthly expiry rule (last Tuesday, from broker notices) verified against Dhan's expired-option dates. Calendar dates only, from pre-window data. Until then, it is an assumption.
3. Lot sizes per session from the scrip master, checked for each instrument.
4. The reference fingerprint above reproduced by the run.
5. The holdout policy in `HOLDOUT.md` in force: operational monitoring only, no P&L review for decisions, and any review logged.
6. Lab runs imported into the ledger.
7. The end date written before any session in the window is viewed.

### Record

Result: pending. The freeze date, dataset manifest, commit and ledger sequence are recorded here at freeze.
