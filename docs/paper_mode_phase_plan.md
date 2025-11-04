# Paper Mode Implementation Phases (Production-Ready, 2025-10-30)

This file tracks all major steps, context, and tasks for the clean migration to the new daily, Redis+Postgres-backed Paper Mode per design.

---

## 🛠️ Phase 1: Foundations and Migrations

**Goal:** Prepare the database and service scaffolding so both modes can switch over cleanly.

- [ ] **Migrate:**
  - `paper_daily_wallets` and `paper_fills_logs` tables with required columns/indexes.
- [ ] **Models:**
  - Add `PaperDailyWallet` and `PaperFillsLog` models.
- [ ] **Trading Date Helper:**
  - `Paper::TradingClock` (single IST-based source of truth for paper Redis namespacing).

---

## 🛠️ Phase 2: Redis Intraday Paper Gateway

**Goal:** Implement the new `Paper::Gateway` (per-day namespaced, with all wallet, position, and orders logic as per spec)—not disturbing live trading.

- [ ] Implement `Paper::Gateway`:
  - All wallet/position/order actions go through the new Redis/in-memory architecture.
  - Per-order charge and exact `used_amount` logic (as described).
  - MTM and equity update on tick.
- [ ] Remove/Deprecate old PaperWallet impl:
  - Identify and remove previous `PaperWallet`/`PaperWallet` references, Redis keys, and services no longer needed.
  - Ensure all `Orders.config` calls globally point to the correct `Paper::Gateway` or `Live::Gateway`.
- [ ] Logging:
  - `orders` and `fills` logs as Redis lists, daily namespaced.

---

## 🛠️ Phase 3: Persistence & EOD/PG Logging

**Goal:** Persist all relevant data in Postgres at EOD and for fills.

- [ ] ActiveJob for each fill → Postgres
- [ ] EOD rollup service (`Paper::EodRollup`):
  - Summarize day, persist `PaperDailyWallet` row.
  - Robust against re-runs.
  - Schedule with cron or background jobs.

---

## 🛠️ Phase 4: API, Console, and Helpers

**Goal:** Provide UI/API observability and CLI helpers for all new state.

- [ ] API Controller:
  - Add `Api::Paper::StateController` with all required endpoints.
  - Remove/deprecate old paper-only endpoints after migration.
- [ ] Console/RAKE Helpers:
  - Intuitive helpers (wallet, positions, day summary).
  - Documented for usage.

---

## 🛠️ Phase 5: Testing, Verification & Doc Update

**Goal:** Ensure zero live-mode disruption, rigorous behavior in all edge and EOD conditions.

- [ ] Test Cases:
  - Units for pricing/charging, MTM, day roll.
  - Integration: ticks → buys → equity → sells → EOD.
- [ ] Docs:
  - README, internal docs, and API contract.

---

### Transition/Cleanup of Earlier Paper Wallet Code
- As we build:
  - Mark obsolete classes with `# TODO: REMOVE` or `# DEPRECATED: superseded by ...`
  - Ensure nothing in Signal, RiskManager, etc, references old paper wallet code.
  - If needed: data migration of old open positions to new Redis scheme for smooth handoff.

---

## Status Tracking
- Update checkboxes and notes as each phase completes, or as subtasks/issues emerge.

---
