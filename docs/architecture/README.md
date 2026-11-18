# Architecture diagrams

Six levels, from the system context down to the code and the build. Each diagram is a standalone HTML page. Open it in a
browser; no server is needed. The typed JSON under [`source/`](source/) is the editable source for each page.

Every diagram is pinned to commit `79e951f07c22d772e412cf35abf2843baa17102a` of this repository. Components, states and
messages cite `file:line` at that commit (evidence is `local-only`: the pages show the file and line, with no web links).
When the code changes, regenerate the affected page rather than editing its HTML. The pages were generated with the
Archify skill (see [Regenerate a page](#regenerate-a-page)).

## Level 0: context

| Diagram | What it shows |
| --- | --- |
| [System context](00-system-context.html) ([source](source/00-system-context.json)) | The operator, the session runner, the agent, DhanHQ, the sandbox, Ollama, alerts, paper_exchange, the offline Time Machine, and what stays on the local host. |

## Level 1: planes, pipeline and deployment

| Diagram | What it shows |
| --- | --- |
| [Layers and planes](01-layers-and-planes.html) ([source](source/01-layers-and-planes.json)) | The layers of [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md), their dependency direction, and the offline research plane with no broker path (ADR-001). |
| [Market to order pipeline](02-market-to-order-pipeline.html) ([source](source/02-market-to-order-pipeline.json)) | The data path from a WebSocket tick to a placed order, with the gates and the durable intent in order. |
| [Configuration and modes](02a-config-and-modes.html) ([source](source/02a-config-and-modes.json)) | How a run is decided: the environment, the YAML profile, the merge, the startup refusals, and the venue for each mode. |
| [Deployment and runtime](02b-deployment-and-runtime.html) ([source](source/02b-deployment-and-runtime.json)) | Where each part runs: the local host, the cron-started tmux session, PostgreSQL and Redis, the external systems, and the CI runner. |

## Level 2: one diagram per layer

| Diagram | Layer |
| --- | --- |
| [Market data and time](03-market-data-and-time.html) ([source](source/03-market-data-and-time.json)) | Config, auth, the Dhan client, market data, the feed, the scrip master, and the clock guard. |
| [Signal and contract](04-signal-and-contract.html) ([source](source/04-signal-and-contract.json)) | The strategy families, market context, the chain, contract selection, bracket levels and sizing. |
| [Risk and advice](05-risk-and-advice.html) ([source](source/05-risk-and-advice.json)) | The trading gate, the rollout policy, the pre-trade gate, the day book, all-in loss, the advisor, and the kill switch. |
| [Execution venues](06-execution-venues.html) ([source](source/06-execution-venues.json)) | The execution port and its four destinations, and the single path to the broker. |
| [Orchestration](07-orchestration.html) ([source](source/07-orchestration.json)) | The runtime wiring, the orchestrator, one agent per index, the serial queue, and the operator inputs. |
| [Audit, persistence and cockpit](08-audit-persistence-cockpit.html) ([source](source/08-audit-persistence-cockpit.json)) | The journal, the PostgreSQL ledger and its immutability, day restore, Redis, alerts, and the cockpit view. |
| [Research plane](09-research-plane.html) ([source](source/09-research-plane.json)) | Dhan data to a verdict: fetch, replay, judge and record, with pre-registration before a confirmation. |

## Level 3: behaviour

| Diagram | What it shows |
| --- | --- |
| [Trade lifecycle](10-trade-lifecycle.html) ([source](source/10-trade-lifecycle.json)) | The normal path of the per-side state machine, with every exit and the protective close. |
| [Client-side protection](10a-client-side-protection.html) ([source](source/10a-client-side-protection.json)) | Paper and sandbox stops that fire only on option ticks: the silence watch, entries refused, and the STALE_DATA exit after the grace period. |
| [Halt and recovery](10b-halt-and-recovery.html) ([source](source/10b-halt-and-recovery.json)) | Every HALT, both UNCONFIRMED triggers, and RESET as defined in the table. Together with the lifecycle, this covers every row of `TRANSITIONS`. |
| [Broker P&L exit](10c-broker-pnl-exit.html) ([source](source/10c-broker-pnl-exit.json)) | The opt-in live rail: arming at start, a refused arm retried per entry, and an unknown outcome that is never resent. |
| [Daily-loss breach](10d-daily-loss-breach.html) ([source](source/10d-daily-loss-breach.json)) | The breach latch, the entries blocked, the DAILY_LOSS flatten, and the broker kill switch once every agent is flat. |
| [Operator controls](10e-operator-controls.html) ([source](source/10e-operator-controls.json)) | Each cockpit key, which ones need a second press, and the orchestrator call each one makes. |
| [Entry sequence](11-entry-sequence.html) ([source](source/11-entry-sequence.json)) | From a closed bar through the chain, the risk gate, the advisor, the durable intent, and the placed order. |
| [Exit with an unknown outcome](12-exit-and-unknown-outcomes.html) ([source](source/12-exit-and-unknown-outcomes.json)) | An ambiguous exit, the halt, the kill switch, and reconciliation. |
| [Startup and recovery](13-startup-and-recovery.html) ([source](source/13-startup-and-recovery.json)) | Lease, day restore, the broker checks, and the warm-up before the first tick. |
| [Session day](13a-session-day.html) ([source](source/13a-session-day.json)) | The day from the weekday start to the last exit, by time window, with the cron boundary and the holiday gap stated. |

## Level 4: data

| Diagram | What it shows |
| --- | --- |
| [Persistence schema](14-persistence-schema.html) ([source](source/14-persistence-schema.json)) | Every table and column the migrations create, the keys, and the foreign keys. The runner's `schema_migrations` table and the view `v_closed_trades` are not drawn. |
| [Journal events](14a-journal-events.html) ([source](source/14a-journal-events.json)) | Every event kind the runtime writes, grouped by purpose, with the line that writes it. |
| [Domain model](15-domain-model.html) ([source](source/15-domain-model.json)) | The order, event and position types, the execution port and its implementations, and the agent and orchestrator. |

## Level 5: code and process

| Diagram | What it shows |
| --- | --- |
| [Code map](16-code-map.html) ([source](source/16-code-map.json)) | Where each layer lives in `src/`, plus `scripts/`, `tests/` and `docs/`. |
| [Module dependencies](16a-module-dependencies.html) ([source](source/16a-module-dependencies.json)) | Which group imports which, with the import counts, and the plane rule checked against the import graph. |
| [Build, test and CI](17-build-test-and-ci.html) ([source](source/17-build-test-and-ci.json)) | The steps a change runs through locally and in CI, and the services CI provides. |

## Regenerate a page

Pages are produced with the [Archify](https://github.com/tt-a1i/archify) skill (`archify/archify/bin/archify.mjs`, a
local checkout). From the repository root, for example:

```bash
ARCHIFY_UPDATE_CHECK_DISABLED=1 node <archify>/archify/bin/archify.mjs finalize architecture \
  docs/architecture/source/00-system-context.json docs/architecture/00-system-context.html \
  --repo-root . --quality showcase --out-dir .archify/review/00-system-context/run-1 --json
```

Use the type from each source (`architecture`, `dataflow`, `lifecycle`, `sequence`, `erd`, `class`, `tree`, `workflow`).
`--out-dir` keeps the receipts out of the repository (`.archify/` is gitignored). The command validates the source,
checks each evidence reference against the pinned commit, renders the page, and runs a browser check. The `.delivery.json`
beside each page is gitignored, because it records absolute paths from the machine that made it. Before regenerating, set each source's `meta.repository.revision` to the commit you pin:
the checker only confirms that a cited line exists in that file at that commit, so a stale pin lets wrong citations pass.

## Maintaining this set

The diagram set is kept only on the branch `archify/architecture-diagrams`. Do not merge the branch into `main`. Keep it
current by rebasing it onto `main`:

1. `git fetch origin && git rebase origin/main`.
2. Set each source's `meta.repository.revision` to the new `origin/main` commit. Regenerate every page with the Archify
   build named below, then run `npm run check`. The checker confirms only that a cited line exists at the pin, so re-read
   each card and label claim against the code at that commit.
3. Commit, then push with `git push --force-with-lease origin archify/architecture-diagrams`. Never force-push `main`.

The current pins are `79e951f`, which is not on `main`. Step 2 replaces them.

**Archify build.** The pages were rendered with Archify (`tt-a1i/archify`, a separate repository) at commit `11b0d60` on
its `main` branch, labelled 3.2.0. That tree differs from the `v3.2.0` release tag: it adds notice blocks to pages and
exports, and its license field reads Apache-2.0 where the tag reads MIT. The release renders the same diagram content
without the notice blocks (checked on page 00). Record the Archify commit whenever you regenerate with a different one.
