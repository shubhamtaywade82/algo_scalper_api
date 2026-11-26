# CLAUDE.md

NSE/BSE index **options-buying** agent on DhanHQ: long CE or PE only, one bracket (stop and target) per entry.
In `MODE=live` this moves real capital. Treat every change under `src/dhan`, `src/execution`, `src/runtime`,
`src/risk`, `src/domain`, `src/options` and `src/strategy` as a change to live money.

## Commands

| Task | Command |
| --- | --- |
| Install from the lockfile (Node 22+) | `npm ci` |
| Full gate, before every commit | `npm run check` (typecheck, build, tests) |
| Typecheck, including `tests/` and `scripts/` | `npm run typecheck` |
| One test file | `npx tsx --test tests/<name>.test.ts` |
| Verify the experiment ledger | `npm run ledger -- verify` |

`npm test` runs every `tests/*.test.ts`. The PostgreSQL and Redis suite runs only when `TEST_DATABASE_URL` and
`TEST_REDIS_URL` are set, and the paper-exchange suite only when `PAPER_EXCHANGE_E2E_URL` is set. In CI both are required.

## Invariants (do not weaken)

Each is a decision in `docs/DECISIONS.md`, and each names what enforces it.

- **Planes (ADR-001).** `src/research`, `src/strategy`, `src/options` and `src/market` never import `src/dhan`,
  `src/execution` or `src/runtime`. Broker writes (`orders`, `superOrders` and `traderControls` place, cancel, modify
  and kill switch) exist only in `src/dhan/liveExecution.ts` and `src/dhan/sandboxGateway.ts`. Test: `tests/architecture.test.ts`.
- **One transition table (ADR-003).** Trade state changes only through `src/domain/fsm.ts`. A (state, event) pair not
  in the table throws. Test: `tests/fsm.test.ts`.
- **Buy to open only, stop and target mandatory (ADR-004).** `EntryOrder.side` is `'BUY'`. `bracketLevels` returns
  nothing without a stop. The pre-trade gate rejects any other side.
- **Unknown outcomes are never replayed (ADR-005).** A timeout, 5xx, 401, 408, 429 or network error becomes
  `*_UNCONFIRMED` and halts the underlying. Only a definitive 4xx becomes `REJECTED`.
- **Fail-closed restart (ADR-006).** Startup refuses while the broker holds an order or a position the agent cannot adopt.
- **Live ceilings are fixed in code.** In `MODE=live`, `loadConfig` refuses `MAX_RISK_PER_TRADE_PCT` above 2 and
  `MAX_DAILY_LOSS_PCT` above 6. Do not change them, or the live risk calculation, outside the ADR-011 rollout policy.
- **The advisor is a veto only.** The LLM can skip an entry. It cannot create one or change size, strike, stop or target.
- **SDK pin.** `@nemesis-oss/dhanhq-sdk` is pinned exactly at 2.0.1. Docs must name the installed version (`tests/docs.test.ts`).
- **Composite keys.** Instruments are identified as `exchangeSegment:securityId`, never by a bare security id.

## Research rules

From `docs/ROADMAP.md` ("Standing rules") and `docs/research/`.

- Do not tune SuperTrend, EMA, or stop and target parameters until a pre-registered hypothesis needs them.
- A period used to choose, tune or diagnose anything is `Spent` (`docs/research/HOLDOUT.md`). A `Spent` period can describe
  the market, but it cannot confirm a hypothesis.
- A confirmation needs a `Frozen` window, a committed entry in `docs/research/PREREG.md`, and a registration with
  `npm run ledger -- register` before the run. Use the `research-experiment` skill.
- Never edit `docs/research/experiments.jsonl` by hand. It is hash-chained, and `npm run ledger -- verify` must pass.
- Research code never writes live configuration, `.env`, or risk limits.

## Working rules

- **Trading-code fix or change:** write a failing test first, against the fake broker in `tests/runtime.test.ts` or the
  adapter tests, then fix, then run `npm run check`. Use the `trading-change` skill.
- **Operator scripts** that reach the broker or the database (`smoke:*`, `reconcile`, `withdraw`, `reset:paper`, `db:*`)
  run only on the operator's explicit instruction.
- **Secrets.** `.env` is gitignored. Never write `DHAN_*` values, API keys, the PIN or the TOTP secret into logs, docs,
  tests or commits. `src/persistence/redact.ts` is the redaction helper.
- **Docs.** Do not write test counts or other numbers that change into prose. `npm test` prints them.
- **Commits.** Conventional form `type(scope): summary`, as in `git log` (`fix(recovery): ...`, `feat(alerts): ...`).

## Developer tooling (ADR-012)

- `.mcp.json` starts `ts-language-mcp`, pinned exactly in `devDependencies` and run from `node_modules`. Claude Code asks
  the operator to approve the project server on first use. Four tools write to disk (`rename_symbol`, `format_document`,
  `apply_code_fix`, `organize_imports`). Never add them to an allow rule, so each use is prompted.
- `tests/tsconfig.json` and `scripts/tsconfig.json` extend the typecheck config so the server analyses those folders.
  Do not delete them.
- Repository skills live in `.claude/skills/`. Personal overrides go in `.claude/settings.local.json`, which is gitignored.

## Codebase graph (ADR-013)

- Build: `scripts/graphify.sh extract . --code-only`, then `scripts/graphify.sh cluster-only .`. After code changes, run
  `scripts/graphify.sh update .`. Requires `uv`. No LLM and no network source is used.
- Read: `scripts/graphify.sh query "<question>"`, `path A B`, `explain X`, `god-nodes`, `affected X`. An edge is `EXTRACTED`
  (stated in the source) or `INFERRED`. Check an inferred edge at its `file:line` before relying on it.
- The graph lives in `graphify-out/`, which is gitignored. `GRAPH_REPORT.md` records the commit it was built from.
- Do not run `graphify install`, `graphify <platform> install` or `graphify hook install` in this repository. They write
  `.claude/settings.json`, CLAUDE.md sections and git hooks (ADR-013). Those need the operator's explicit decision.
