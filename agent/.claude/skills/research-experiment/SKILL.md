---
name: research-experiment
description: Use when running, registering or reporting a Time Machine, context-cell, trail study, holdout or confirmatory test in options-trading-agent, or when editing docs/research/ or the experiment ledger.
---

# Research experiment

A result here can decide what the agent is allowed to trade. The rules are in `docs/ROADMAP.md` ("Standing rules")
and `docs/research/PREREG.md`. Follow them in this order.

1. **Classify the window.** Read `docs/research/HOLDOUT.md`. A window is `Frozen` only when its manifest is committed
   there and no decision has used it. Any other window is `Spent`, and a `Spent` window can only describe the market.
2. **Choose the kind of run.** Discovery and description are allowed on any window. Record them as
   `--type discovery` and do not present them as confirmation. A confirmation (`--type confirmation`) is allowed only
   on a `Frozen` window, after steps 3 and 4.
3. **Pre-register.** Add a `PRE-<yyyy-mm-dd>-<n>` entry to `docs/research/PREREG.md` using the template there. Commit
   it. Then register it:
   `npm run ledger -- register --hypothesis <id> --strategy <id> --underlying <NIFTY|BANKNIFTY|SENSEX> --from <date> --to <date> --type confirmation --holdout Frozen`.
   The ledger refuses a confirmation that has no registration.
4. **Keep the thresholds fixed.** Minimum 30 holdout trades and 30 independent sessions, the best-session test, the
   profit-share cap, the five-session block floor, and cost stress at 1% half-spread and 2× stop slippage
   (`docs/ROADMAP.md`, OTA-308). Do not lower a threshold in a run. A changed threshold is a rule change and is
   reviewed on its own.
5. **Run once.** `npm run timemachine -- run --data <dataset file>`, with `--cells`, `--strategy <id>` or `--shadow` as
   needed. Each run appends to the ledger. Running the same test again on the same window is the same test, not a second chance.
6. **Verify and record.** `npm run ledger -- verify` must print `ledger ok`. Record the result and its ledger sequence
   number in `docs/research/PREREG.md`. A failed hypothesis stays recorded as failed, and the next hypothesis is a new entry.
7. **Never** edit `docs/research/experiments.jsonl` by hand, and never let research code write `config.*.yml`, `.env`
   or any risk limit.
