---
name: trading-change
description: Use when changing or fixing code in src/dhan, src/execution, src/runtime, src/risk, src/domain, src/options or src/strategy of options-trading-agent, or any change that could reach an order, a position, or the day's risk figures.
---

# Trading change

Every change in these folders can move real capital. Work through the steps in order.

1. **Name the invariant.** Find the decision in `docs/DECISIONS.md` and the invariant in `docs/ARCHITECTURE.md`
   (section 3) that the code path relies on. If the change would weaken one, stop and ask the operator.
2. **Reproduce first.** Write a test that fails on the current code. Broker behaviour is tested against the fake
   broker in `tests/liveExecution.test.ts` and `tests/dhanAdapters.test.ts`. Lifecycle behaviour is tested with
   `tests/runtime.test.ts` and `tests/support/fakeRuntime.ts`. Run the file and show the failure:
   `npx tsx --test tests/<file>.test.ts`.
3. **Fix the smallest thing.** Trade state changes go through `src/domain/fsm.ts` only. Broker writes stay in the two venue
   adapters. Do not change the live ceilings in `src/config.ts`, or the live risk calculation, outside the ADR-011
   rollout policy.
4. **Cover the failure modes that apply.** For broker code: a definitive rejection, an ambiguous outcome (which must
   become UNCONFIRMED and never be resent), a partial fill, and stale market data. Deleting an existing case is never
   part of a fix.
5. **Run the gate.** `npm run check`. Typecheck and build must be clean. Report the `# pass` and `# fail` lines from the
   test output, and compare the test count with the count before your change.
6. **Move the docs with the behaviour.** Broker assumptions go to `docs/BROKER_CONTRACT.md`. An operator-visible change
   goes to the matching section of `README.md`. Do not write test counts into prose.
7. **Report.** List the invariants the change touches and the test that proves each one. State what cannot be verified
   offline: live DhanHQ wire behaviour is not covered by tests (README, "Not covered by tests").
