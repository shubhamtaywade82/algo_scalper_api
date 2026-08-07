# PR: Merge `develop` into `main`

**Title (suggested):** Release: merge `develop` into `main` (SMC confluence,
paper-only gate, dashboard Solid, hardening)

## Summary

This promotion brings `develop` into `main` with a large batch of trading, API,
dashboard, and operational work. The diff is substantial (**~645 files**,
**~43.5k insertions / ~18.1k deletions**), so treat this as a **release merge**
rather than a single feature.

## Highlights

- **Paper trading safety (#163)** — Enforces paper-only behavior where intended
  (aligns live vs paper with product expectations).
- **SMC confluence (#162)** — SMC confluence pipeline, related jobs/specs, and
  tighter integration with signal / permission flows.
- **Dashboard (#159)** — Migrates the dashboard from **Vue 3** to **Solid.js**;
  related UI refactors (open positions, polling, favicon, data handling).
- **Market context & permission gating (#147)** — Market-context and
  permission-gate behavior for strategy/signal decisions.
- **Capital allocation** — Capital allocator updates with **effective
  allocation** logic and expanded tests.
- **Signal & LTP** — Improvements to signal processing and LTP resolution.
- **Entry / expiry** — Expiry-week **power trend** guard and entry-guard /
  expiry logic refactors.
- **Data & performance** — Performance indexes on `position_trackers`;
  auditor-style queries moved toward **DB aggregates** where applicable.
- **API layer** — Centralized **API error handling** concern; token/auth
  patterns consolidated (`Api::TokenAuthenticatable`, `Api::ErrorHandling`);
  SMC and signals endpoints evolved (e.g. `smc` under API namespace).
- **Jobs & ops** — AI technical analysis / calibration jobs refactored; SMC
  scanner and tick-AI digest job work; Dhan-related jobs (e.g. auto IP
  updater), public IP logging, Telegram SMC alerts.
- **Models** — `PositionTracker` split into **concerns** (broadcastable,
  indexable, lifecycle, PnL, queryable); derivative / instrument helpers and
  scopes extended.
- **Quality & docs** — `frozen_string_literal: true` across service files;
  broad time-handling cleanup; RSwag / **Swagger** surface expanded; repo docs
  (`AGENTS`, `README`, `CHANGELOG`, audit/summary, TODO); legacy EPIC scenario
  specs disabled for PR checks (#143); **Trading System Hardening PR
  Playbook** added (#137 area + hardening).

## Merged / referenced PRs (from history)

| PR   | Theme                              |
| ---- | ---------------------------------- |
| #163 | Paper trading only                 |
| #162 | SMC confluence                     |
| #159 | Dashboard Vue → Solid.js         |
| #147 | Market context & permission gate   |
| #143 | Disable legacy EPIC scenario specs |
| #137 | Derivative / PositionTracker scopes |

## Verification (pre-merge / post-merge)

Suggested checks on this branch (or CI):

1. `bundle exec rubocop`
2. `bin/brakeman --no-pager`
3. `bundle exec rspec`
4. Smoke: `./bin/dev` — API health, dashboard dev server, trading daemon **in
   paper** with `DHANHQ_ENABLED` / credentials policy used in non-prod.

Note any **DB migrations** from this line of work and run `rails db:migrate` in
each deployed environment before relying on new columns/indexes.

## Risk & rollout notes

- **Large surface area** — Reviewers should lean on CI and focused regression
  around **entries, SMC, permissions, paper/live config**, and **dashboard/API**
  contracts.
- **Config / env** — Compare `.env.example` and `README` to production env; new
  toggles or Dhan auth strategies may need explicit rollout.
- **Swagger / clients** — If external consumers use OpenAPI, point them at
  updated `swagger/v1/swagger.yaml`.

## Rollback

Revert the merge commit on `main` or redeploy the previous `main` image/tag;
ensure DB migrations are **backward-compatible** or plan a down strategy if any
migration is destructive.

## Optional follow-up

To list migrations only:

```bash
git diff main..develop -- db/migrate
```
