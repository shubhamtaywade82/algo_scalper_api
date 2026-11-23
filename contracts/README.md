# Cross-service contracts

Versioned contracts that `algo_scalper_api` (Ruby) and `options-trading-agent` (TypeScript) both
implement. A contract is a JSON Schema (draft 2020-12) plus at least one fixture example. **No
cross-language imports**: the agent vendors a copy of this directory and its CI fails if the copy
drifts from this repo's `main` (drift-check policy below).

This realises decision D9 and component S16 of
[`docs/architecture/UNIFIED_SYSTEM_PLAN.md`](../docs/architecture/UNIFIED_SYSTEM_PLAN.md):
contracts live in this repo (the control-plane repo); the agent vendors and drift-checks them.

## Contract catalog

| Schema | Direction | Transport | Status |
|---|---|---|---|
| [`chain-context-1`](schemas/chain-context-1.schema.json) | Rails -> agent (Redis) | Redis key `dhan:chain:context:{underlying}`, TTL 15 s | **implemented** (Phase 1 / roadmap G1) |
| [`chain-snapshot-1`](schemas/chain-snapshot-1.schema.json) | either -> both (Redis) | Redis key `dhan:chain:{underlying_security_id}:{expiry}` | proposed (plan S3) |
| [`trade-intent-1`](schemas/trade-intent-1.schema.json) | Rails -> agent | `GET /api/trade_intents?after=<cursor>&mode=<mode>` (operator token) | proposed (plan §7.1, Phase 3) |
| [`intent-outcome-1`](schemas/intent-outcome-1.schema.json) | agent -> Rails | `POST /api/trade_intents/:intent_id/outcome` (operator token) | proposed (plan §7.2, Phase 3) |
| [`agent-snapshot-1`](schemas/agent-snapshot-1.schema.json) | agent -> Rails (Redis) | Redis key `trading:agent:snapshot`, TTL 10 s | proposed (plan §7.4 / S15) |
| [`vix-snapshot-1`](schemas/vix-snapshot-1.schema.json) | Rails -> consumers | `GET /api/market/vix` (dashboard token; endpoint exists) | proposed (advisory; roadmap G2) |
| [`iv-snapshot-1`](schemas/iv-snapshot-1.schema.json) | Rails -> consumers | REST (endpoint lands with G2) | proposed (advisory; roadmap G2) |
| [`greeks-snapshot-1`](schemas/greeks-snapshot-1.schema.json) | Rails -> consumers | REST (endpoint lands with G3) | proposed (advisory; roadmap G3) |

Already-deployed integrations that are **not** JSON Schema contracts (byte-level or config-level):

- **Token authority**: `GET /api/dhan/token` guarded by `Authorization: Bearer <API_OPERATOR_TOKEN>`;
  the agent presents the same key via `DHAN_TOKEN_AUTHORITY_KEY` (merged, agent PR #14).
- **Shared rate budget**: byte-identical Lua slot script on Redis key `dhan:rate_limit:option_chain`
  (3 s per account); the agent sets `DHAN_SHARED_RATE_LIMIT_KEY=dhan:rate_limit:option_chain`.

## Envelope: trade-intent polling

`GET /api/trade_intents?after=<cursor>&mode=<mode>` returns oldest-first intents plus a control block:

```json
{
  "schema": "trade-intents/1",
  "cursor": "8f6c1a52-3d47-4b9a-9f2e-6c1d5a7b9e01",
  "intents": [ { "...": "trade-intent/1 objects" } ],
  "control": {
    "circuit_breaker": { "tripped": false },
    "intake_enabled": true,
    "server_time": "2026-11-23T09:31:02.114+05:30"
  }
}
```

The agent stops accepting when `tripped` is true, `intake_enabled` is false, or `server_time` skews
more than a configured limit from its own clock. Semantics (idempotency, expiry, slot-busy, first
wins, failure behaviour) are specified in plan §7.3 of `UNIFIED_SYSTEM_PLAN.md` and remain normative.

## Versioning rules

1. Names carry a major version: `trade-intent-1` -> `trade-intent-2`. A major bump is a new file; the
   old one stays until both sides have migrated.
2. **Additive** changes (new optional properties, new enum values a consumer must tolerate) bump the
   `description` changelog line only; existing fixtures must keep validating.
3. **Breaking** changes (removing/renaming fields, tightening types, new required fields) require a
   new major version and a migration note in the schema description.
4. Every schema change ships with an updated fixture; CI validates fixture-against-schema in both
   repos, so a fixture that stops validating fails both pipelines.
5. Numbers stay numbers, nullable fields stay nullable: `null` means "the writer does not have this
   datum", never "zero".

## Drift-check policy (to be wired in both repos' CI - roadmap G0)

- The agent vendors `contracts/` verbatim (no edits) at `options-trading-agent/contracts/`.
- A scheduled CI job in the agent repo diffs the vendored copy against this repo's `main`; any diff
  fails the build and points here.
- Contract tests: each side validates every fixture in `contracts/fixtures/` against its schema
  using its own JSON Schema validator (this repo: the `json_schemer` gem; the agent: a Node
  validator), so the same fixtures run through both language stacks.
- The Redis Lua rate-gate script gets the same treatment: one canonical copy here, vendored by both,
  plus a cross-repo test that runs both implementations against one Redis instance and asserts
  identical spacing.

## Local validation

```bash
pip install jsonschema
python3 contracts/scripts/validate_contracts.py
```

Validates every fixture against its schema (currently 8/8 OK). The Ruby-side validator (json_schemer)
lands with the G0 CI wiring.
