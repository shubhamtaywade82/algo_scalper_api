# Architecture decisions

The decisions the roadmap (`docs/ROADMAP.md`) and the target design depend on. Each entry says where it is enforced.
A decision is changed by a new entry that supersedes the old one, not by editing the old one.

Enforcement levels: **test** (a failing test catches a violation), **type** (the compiler does), **review** (only the
review checklist does). Review-only decisions are called out as such.

---

## ADR-001 Trading and research are separate planes

**Context.** A research result must never reach a live order without a human decision.

**Decision.** `src/research/`, `src/strategy/`, `src/options/` and `src/market/` never import `src/dhan/`,
`src/execution/` or `src/runtime/`. Broker writes (`orders`, `superOrders`, `traderControls` place, cancel, modify and
kill-switch calls) exist only in `src/dhan/liveExecution.ts` and `src/dhan/sandboxGateway.ts`.

**Enforced by.** test: `tests/architecture.test.ts`.

## ADR-002 Keep the existing module layout

**Context.** The proposal's `domain/ market/ strategy/ options/ ai/ …` tree would move every file to fix nothing.

**Decision.** New code goes into the existing folder that owns the concern. The tree in `docs/ARCHITECTURE.md` is the
map. No mass move.

**Enforced by.** review.

## ADR-003 The trade lifecycle is one transition table

**Context.** Ambiguous transitions are how an unmanaged position appears.

**Decision.** `src/domain/fsm.ts` is the only source of trade-state transitions. A (state, event) pair not in its table
throws `IllegalTransitionError` and leaves the state unchanged. HALT is never legal inside HALTED.

**Enforced by.** test: `tests/fsm.test.ts`; type for the state and event unions.

## ADR-004 Buy-to-open only, with a mandatory stop and target

**Context.** The agent trades long CE and PE options only. Option selling is out of scope.

**Decision.** `EntryOrder.side` is the literal `'BUY'`. The pre-trade gate rejects any other side. A bracket without a
stop or target is never built. Risk is recomputed from the order's own numbers, not from the sizing step.

**Enforced by.** type (`side: 'BUY'`); test: `tests/riskEngine.test.ts` (`NOT_A_BUY_ORDER`, `STOP_LOSS_INVALID`,
`TARGET_INVALID`, `RISK_EXCEEDS_BUDGET`).

## ADR-005 An unknown broker outcome is never replayed

**Context.** A write that timed out may still have reached the matching engine. Sending it again can double the trade.

**Decision.**
- Only a definitive client rejection is `REJECTED`: a validation error, or a 4xx other than 401, 408 and 429. Everything
  else is `UNCONFIRMED`, which halts the underlying (`classifyPlacementError`).
- An exit SELL whose outcome is unknown blocks any further SELL for that position until a definitive outcome arrives
  or reconciliation shows the position flat. Added 2026-11-03 (`70c7f57`); before it, a second `submitExit` could send
  a second SELL for the same quantity.

**Enforced by.** test: `tests/liveExecution.test.ts` ("ambiguous exits (failure injection)" and
"classifyPlacementError").

## ADR-006 Restart is fail-closed

**Context.** A restart resets in-memory state. Whatever the broker holds, and whatever the journal cannot prove, must
not be silently forgotten.

**Decision.**
- Startup refuses while the broker shows an open option position or a live order (`orchestrator.ts` `startInternal`).
- The day book is rebuilt from today's journal only. A malformed line refuses startup.
- An entry journalled as submitted with no outcome is booked at its all-in adverse loss, not at zero.
  It is not booked at zero, because the bracket may have closed it during the outage. Since OTA-311 the booking is the all-in
  adverse loss (planned stop distance, stop slippage and charges, `risk/allInLoss.ts`), and it always applies. A superseded unresolved entry is
  booked the same way when a new entry for that underlying appears. Added 2026-11-03 (`07d0778`).
- An unresolved entry without a usable stop or tick refuses startup, because there is no loss to book.

**Enforced by.** test: `tests/dayState.test.ts`; `tests/runtime.test.ts` for the broker-state refusals.

## ADR-007 Research data is files with a manifest; experiment accounting is the ledger (see ADR-010)

**Context.** Eleven PostgreSQL research tables would cost weeks before any query needs them.

**Decision.** Datasets are JSON files. Each replay appends one line to `runs.jsonl` with the dataset's SHA-256 and the
verdict. Failed runs stay in the file so they count against the multiple-testing correction. Revisit when a query
cannot be answered from the manifest.

**Enforced by.** review. The manifest fields are produced by `scripts/timemachine.ts`.

## ADR-008 Verdicts are deterministic and the model cannot change them

**Context.** An LLM that can flip a verdict can promote noise.

**Decision.** The Time Machine verdict is `TimeMachineVerdict` (`INSUFFICIENT_EVIDENCE`, `NO_TRADE`, `EDGE_SUPPORTED`),
computed on the holdout only: its bootstrap interval, its mean, its trade count and its session count, then the same rules under two cost stresses (`docs/ROADMAP.md`, OTA-308). The advisor is a veto with two
outputs; any failure is SKIP.

**Enforced by.** test: `tests/timeMachine.test.ts` (verdict cases); review for the advisor.

## ADR-009 The proposal's contracts map onto types that already exist

**Context.** The proposal lists twelve domain contracts. Most are already implemented under other names. Renaming them
would churn every caller.

**Decision.** Keep the existing names. Add a new contract only when a second caller needs it. Version identifiers are
not added to these types. Research reproducibility is carried by the manifest (`dataSha256`, OTA-202).

| Proposed contract | Existing type | Location |
| --- | --- | --- |
| MarketSnapshot | `Tick`, `Candle[]` | `src/domain/types.ts` |
| MarketContext | `MarketContext` | `src/strategy/marketContext.ts` |
| StrategyDefinition | `STRATEGY_CATALOG`, `StrategyId` | `src/strategy/session.ts` |
| StrategySignal | `Signal` | `src/domain/types.ts` |
| OptionContract | `OptionContract` | `src/domain/types.ts` |
| OptionQuote | `OptionQuote` | `src/domain/types.ts` |
| RiskVerdict | `RiskVerdict` | `src/risk/riskEngine.ts` |
| OrderIntent | `EntryOrder`, `ExitOrder` | `src/execution/ports.ts` |
| ExecutionReport | `ExecutionEvent` | `src/execution/ports.ts` |
| PositionSnapshot | `OpenPosition`, `DaySnapshot` | `src/domain/types.ts`, `src/risk/dayBook.ts` |
| Experiment | one `runs.jsonl` line | `scripts/timemachine.ts` |
| ValidationReport | `TimeMachineVerdict` and report | `src/research/timeMachine.ts` |

## ADR-010 Experiment accounting is an immutable, hash-chained ledger

**Context.** A divisor that comes from a log, a seed file, or a dataset hash can be reset by changing the dataset. A new hash
is not a new independent experiment, and the count must keep every variant ever tested.

**Decision.** Every research variant is one record in `docs/research/experiments.jsonl`, committed to git. Each record carries
its hypothesis, strategy, parameter fingerprint, dataset hash, date range, overlap group, experiment type, holdout status,
cost fingerprint, provenance, result and creation time. Records are sealed into a hash chain, so editing, removing or
reordering one fails verification, and no count is taken from a broken ledger. The divisor is the ledger's program-wide sum.
A confirmation needs a registration made before it, on a Frozen window. A Spent window can only be a backfill.

**Enforced by.** test: `tests/experimentLedger.test.ts`, and `tests/committedLedger.test.ts` for the committed file.

## ADR-011 All-in risk is a rollout policy, not a silent change

**Context.** The planned stop distance understates what a stop can cost. Replacing the live calculation without evidence would
change real capital exposure without a test of the replacement.

**Decision.** `ALL_IN_RISK_POLICY` selects `off`, `shadow` or `enforce`. Every entry journals its planned risk and its all-in
adverse loss. `off` and `shadow` decide on planned risk, unchanged. `shadow` also records whether the all-in budget would have
refused the entry, and paper runs in this mode. `enforce` decides on all-in risk, and in live mode it also needs
`ALL_IN_RISK_LIVE_ACK`, an operator sign-off. Realised net losses are compared with the all-in figure by
`scripts/risk-shadow.ts`, which counts losses that exceed it, including gaps through the stop.

**Enforced by.** tests: `tests/riskEngine.test.ts` (basis and policy), `tests/riskShadow.test.ts`, `tests/config.test.ts` (the
policy names, the paper setting and the live guard).

## ADR-012 Development tooling is dev-only, exactly pinned and read-first

**Context.** A coding assistant works faster from the compiler's own answers than from text search. A server that floats to
the newest version, enters the runtime dependency tree, or writes files without a prompt would change what the repository
builds and what an assistant can do to it.

**Decision.** The TypeScript code-intelligence server is a `devDependency` pinned exactly (`ts-language-mcp` 2.3.1). `.mcp.json`
starts it from `node_modules`, never from an unpinned `npx` download. It has no runtime dependency, and no file in `src/` or
`scripts/` imports it or the MCP SDK. Its four tools that write files (`rename_symbol`, `format_document`,
`apply_code_fix`, `organize_imports`) are never pre-allowed, so each use is prompted. Its read-only tools may be pre-allowed in
a project settings file. `tests/tsconfig.json` and `scripts/tsconfig.json` extend the typecheck config, so the server analyses
those folders. Repository skills in `.claude/skills/` are instructions that point at existing docs and scripts. They add no
code path to the trading or research planes. Upgrading the server is a deliberate change: compare its tool list with this
policy, then update the pin and the docs together.

**Enforced by.** test: `tests/devTooling.test.ts` (exact pin equal to the installed version, not a runtime dependency, started
from `node_modules`, no import in `src` or `scripts`, per-folder tsconfigs, personal settings gitignored, skill names and
descriptions). review: the writer policy. No test sees it until a project settings file exists.

## ADR-013 Graphify is an offline, dev-only codebase map

**Context.** A knowledge graph of the code (definitions, call and import edges, communities, rationale nodes) gives an assistant
structure that text search does not. Graphify also ships an assistant installer that writes Claude settings, CLAUDE.md sections
and git hooks, and an extraction path that can send documents to a model or write to a global graph. ADR-012 governs this
repository's permission and hook configuration, and research records must not leave the machine unreviewed.

**Decision.** `scripts/graphify.sh` runs the pinned `graphifyy` 0.9.104 through `uvx`, sets `GRAPHIFY_BACKEND=none`, and allows
only `extract --code-only`, `update`, `cluster-only`, `query`, `path`, `explain`, `god-nodes` and `affected`. Code is parsed
locally with tree-sitter. The output is `graphify-out/`, which is gitignored. The repository never runs `graphify install`,
`graphify <platform> install` or `graphify hook install`, because those write `.claude/settings.json`, CLAUDE.md sections and git
hooks. Those choices belong to the operator. The graph is a navigation aid. Compiler-accurate definitions and references still
come from `ts-language-mcp`, and an inferred edge is checked at its cited `file:line` before anyone relies on it.

**Enforced by.** test: `tests/devTooling.test.ts` (exact pin in the wrapper, allow-list limited to the offline commands,
`--code-only` required for extract, `graphify-out/` ignored). review: any change to the allow-list or to the installed integrations.

## ADR-014 A client-side stop is watched for silence, and the broker P&L exit is an opt-in live rail

**Context.** Paper and the sandbox gateway hold the stop and target in the agent. Those levels fire only when option ticks
arrive, so a silent feed leaves an open position with no working stop, and nothing records that it is unprotected. The live
venue holds the stop as a super-order leg at the exchange, which does not depend on the agent's feed. The daily-loss brake is
local. The broker also has a daily P&L exit (`traderControls.setPnlExit`), which the adapter did not use.

**Decision.** Each execution port declares its protection (`ExecutionPort.protection`): `EXCHANGE_BRACKET` for live,
`CLIENT_SIDE` for paper, Postgres paper and the gateway. The cockpit labels a client-side stop, and the journal records the
protection on `entry_filled` and `position_client_side`. For a client-side position, silence on option ticks longer than
`FEED_STALE_MS`, counted from the later of the fill and the last tick, journals `position_stale` and refuses entries on that
underlying. Past `STALE_POSITION_GRACE_MS`, which must be at least `FEED_STALE_MS`, the position exits with reason `STALE_DATA`
through the normal exit path, where `exitSent` keeps it to one sell. Live positions are not watched by this rule. In live mode
with `BROKER_PNL_EXIT=true`, the adapter sets Dhan's daily loss exit at start to the daily loss limit, with
`enableKillSwitch: false` (invariant 7). The request is a broker write under ADR-005. A definitive refusal is tried again by the
next entry. Any ambiguous outcome is never resent, and every entry is refused as unconfirmed until restart.

**Consequences.** The watch measures silence in the option's own ticks, so it cannot tell a dead feed from a strike that has not
traded. A grace shorter than a quiet strike's trade gap closes that position. The watch affects paper and sandbox runs only. The
broker P&L exit is off by default, because its `lossValue` sign and units, its action when it fires and its persistence across
sessions are unverified (BROKER_CONTRACT row 1.9). A refused arm at start does not stop the agent; it refuses entries. Research
does not import the runtime or the execution ports (ADR-001), so the watch cannot change a research result.

**Enforced by.** tests: `tests/runtime.test.ts` ('stale option ticks on an open client-side position', 'broker P&L exit arming
at start'), `tests/gatewayPort.test.ts` ('GatewayExecutionPort protection, trailing stop and gap-through'),
`tests/liveExecution.test.ts` ('LiveExecutionPort protection and the broker P&L exit'), `tests/config.test.ts`
('stale-position grace and broker P&L exit settings'), `tests/cockpit.test.ts` ('position protection label').

## Deliberately not decided yet

Each waits for a concrete need, as `docs/ROADMAP.md` states: a strategy registry service, a Zod schema for every domain
object, OpenTelemetry, the PostgreSQL research schema, and a Redis-backed research store. Research code does not use Redis;
Redis serves the runtime's cache, rate gate and lease (`src/persistence/`).
