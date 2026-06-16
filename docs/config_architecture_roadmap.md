# Config Architecture Roadmap

Hardening the algo config system for an autonomous options-buying engine. Goal:
**deterministic, auditable, reproducible** config — env = mode/secrets, YAML = reviewed
defaults, DB = audited live overrides, tier single-sourced, config frozen per open
position, stamped on every trade, validated on write.

This document is the plan of record. Phase 1 is implemented; Phases 2–4 are designed but
not built.

---

## Background: how config resolves today

`AlgoConfig.fetch` (30s in-process cache) builds the effective config in this order
(`app/lib/algo_config.rb`):

1. **`DocumentStore.current_mutable_document`** — canonical base. The **DB document**
   (`settings.algo_config_document`, full snapshot). `config/algo.yml` only *seeds* it on
   first use; legacy `algo_config_overrides` merged once at bootstrap.
2. **Signal tier preset** (`config/signal_tier_presets.yml`) deep-merged on top.
3. **`LIVE_TRADING`** env → forces `paper_trading.enabled`.
4. **`PAPER_STRICT_DIRECTION_GATE`** env → paper-mode direction-gate relax.

All mutations funnel through `DocumentStore#persist!` → `Setting.put` +
`AlgoConfigChangeLog` audit row + `AlgoConfig.reset!`.

### Problems this roadmap fixes

- DB doc is a **full snapshot**, so `config/algo.yml` is inert at runtime (confusing; YAML
  edits silently do nothing).
- **No validation** on writes — a bad value persists and kills trades or blows risk.
- Config **re-read live every tick** in exit/trailing code → a mid-position change moves an
  **open** position's stop.
- **No config identity per trade** — can't reconstruct which gates/params were active for a
  given trade. `AlgoConfigChangeLog` exists but is orphaned (no version, not joined to trades).
- **`signal_tier` diverges** across YAML / DB / env with env silently winning.
- `Positions::TrailingConfig` is a **global memoized module**, never `reset_config!`'d →
  trailing params are accidentally frozen-at-boot and global, not per-position.

---

## Phase 1 — Safe high-value hardening  ✅ IMPLEMENTED

Status: done, TDD, 72 specs green, zero new regressions. Not yet committed.

| Item | What | Key files |
|------|------|-----------|
| 1.1 Write-validation (hard reject) | `AlgoConfig::Validator` checks range/type/enum for the dangerous gates; wired into `DocumentStore#persist!` (validates changed subtrees only); raises `AlgoConfig::ValidationError`. API → 422 `{errors:[…]}`, nothing persists. Covers calibration auto-apply too. | `app/services/algo_config/validator.rb`, `document_store.rb`, `api/settings_controller.rb` |
| 1.2 `signal_tier` single source | Doc `signals.signal_tier` is primary. `SIGNAL_TIER` env ignored (loud WARN) unless `SIGNAL_TIER_FORCE=true`. Reconciled live divergence to `standard`. | `app/lib/algo_config.rb#resolve_signal_tier`, `config/algo.yml` |
| 1.3 Stamp config on every trade | `AlgoConfig.version` = `{hash, change_log_id}`; stamped on `TradingSignal.metadata` and every `PositionTracker.meta[:config_version]`. | `app/lib/algo_config.rb#version`, `entries/meta_builder.rb`/`entry_guard.rb`, `models/trading_signal.rb` |
| 1.4 Pin config per open position (partial) | `Positions::ExitConfigResolver.for(tracker)` returns the entry-time snapshot (`meta[:config_snapshot]`, secrets excluded) or live fallback. Routed the 4 per-tick read sites through it. | `app/services/positions/exit_config_resolver.rb`, `live/unified_exit_checker.rb`, `live/risk_manager_service/exit_enforcement.rb`, `orders/trailing_engine.rb`, `orders/mfe_exit_engine.rb` |

Deferred out of Phase 1 (moved to Phase 2): `TrailingConfig` per-position pinning + its
frozen-at-boot bug; the sparse-override merge model.

Activation note: code changes require a **trading-daemon restart**; DB-doc/tier changes are
live within the 30s cache.

---

## Phase 2 — Sparse overrides, versioning, full pinning

Goal: make YAML meaningful again, give config first-class versions/rollback, and finish
per-position pinning. Larger blast radius on `AlgoConfig` core + LOCKED exit plumbing — ship
behind the Phase 1 test net.

### 2.1 Sparse-override merge model

Invert the base: `config/algo.yml` becomes the **live base** (re-read each `fetch`), DB stores
**only changed keys** (a sparse override hash). Effective = `deep_merge(YAML, sparse_override)`
→ tier → env.

- Repurpose/添加 a DB key (e.g. `algo_config_overrides_v2`) holding the sparse diff;
  `DocumentStore` writes patches into the diff, not a full snapshot.
- `current_mutable_document` returns `deep_merge(yaml_seed, sparse_override)` (keeps callers
  working).
- **Data migration**: diff the current full DB doc against `algo.yml` to extract the existing
  sparse override (one-time, idempotent, reversible — keep the old doc as backup).
- Keep `AlgoConfigChangeLog`; `changed_paths` now also reflects which override keys moved.

Risk/contract to preserve: merge semantics (`MergeUtil`), 30s cache, tier overlay order,
`force_bootstrap!`.

### 2.2 `AlgoConfigVersion` model (already anticipated)

`WeeklyCalibrationJob` references a `AlgoConfigVersion` stub (`propose_config!` is a no-op).
Build it for first-class versioning + rollback.

- Table: `id, content_hash, sparse_override (jsonb), source, actor, change_log_id, created_at`.
- On each persist, create a version row (hash of effective config). `AlgoConfig.version`
  (Phase 1) returns this row's id/hash.
- Rollback endpoint/rake: re-apply a prior version's sparse override (audited).
- Wire `CalibrationRun#propose_config!` / `WeeklyCalibrationJob` to emit a proposed version
  instead of a silent no-op.

### 2.3 Finish per-position pinning (`TrailingConfig`)

`Positions::TrailingConfig` is a global `module_function` module with memoized `@config`,
used by `unified_exit_checker`, `orders`/`trailing` engines, `profit_manager`,
`peak_drawdown_rule` (5 files). Pin it per-tracker.

- Refactor `TrailingConfig` to accept a config (the tracker's pinned snapshot) instead of
  reading global `AlgoConfig.fetch[:risk]` — e.g. `TrailingConfig.for(snapshot)` returning a
  small value object, or thread the resolved config through call sites.
- Remove the never-reset memoization (`@config ||=` + absent `reset_config!`) — current
  behavior freezes trailing params at process boot, which is a latent staleness bug.
- Route the 5 callers through `ExitConfigResolver.for(tracker)`.

Constraint: LOCKED layer (CLAUDE.md). Justify under Critical Scenario #2/#3 (open-position
stop integrity). Smallest viable change; preserve idempotency + linear lifecycle.

### Phase 2 tests
- Sparse merge: YAML default + sparse override → effective; absent override = pure YAML.
- Migration: extract → re-merge reproduces the pre-migration effective config exactly.
- `AlgoConfigVersion`: persist creates a version; rollback restores prior effective config.
- `TrailingConfig` pinning: mid-position change does not alter an open tracker's tier/SL; a
  new tracker picks up the change.

---

## Phase 3 — Validation depth, diff/rollback UX, observability

### 3.1 Expand the validation schema
Grow `AlgoConfig::Validator::RULES` to cover the full risk/exit/sizing surface (cross-field
invariants too, e.g. `stop_loss < profit_target`, trailing tier monotonicity). Optionally move
to a declarative schema file. Keep hard-reject.

### 3.2 Config diff + rollback in the dashboard
- `GET /api/settings/change_logs` already exists; add a **diff view** (before/after per
  `changed_paths`) and a one-click **rollback** to a prior `AlgoConfigVersion`.
- Surface the effective tier + divergence warnings (1.2) in the UI so a stray `SIGNAL_TIER`
  env is visible, not silent.

### 3.3 Observability
- Expose `AlgoConfig.version` on the health endpoint and in trade/exit logs so every exit line
  can be tied to a config version.
- Join `AlgoConfigChangeLog` → trades (via stamped `config_version`) for post-mortems:
  "what changed right before the losing streak?"

---

## Phase 4 — Env hygiene & secrets separation

- Audit all trading env vars (`LIVE_TRADING`, `SIGNAL_TIER(_FORCE)`, `PAPER_STRICT_DIRECTION_GATE`,
  `BACKTEST_MODE`, `SCRIPT_MODE`, `DISABLE/ENABLE_TRADING_SERVICES`, `PLACE_ORDER`,
  `ENABLE_ORDER`, `DHANHQ_WS_*`). Document each: who reads it, what it gates, default.
- Enforce the rule **env = mode/secrets only**; strategy params never in env.
- Confirm credential sections (`dhanhq`, `telegram`, `ai`) never land in persisted snapshots
  (Phase 1 already excludes them from `position_snapshot`) or in `AlgoConfigChangeLog`
  (redaction exists — add a test that asserts it).

---

## Cross-cutting principles

- **One runtime truth** (YAML base + sparse DB override after Phase 2); env only for mode/secrets.
- **Every write audited + validated**; every config state has a version.
- **Freeze config for the life of an open position**; entry gates read live.
- **Stamp config version on every trade** for reproducibility.
- **Touch LOCKED exit/risk plumbing only** under a Critical Scenario, smallest viable change.

## Sequencing

Phase 1 (done) → commit behind a branch → Phase 2 (sparse + versioning + TrailingConfig
pinning, one PR each sub-item) → Phase 3 (UX/observability) → Phase 4 (env/secrets audit).
Each phase is independently shippable and paper-mode-safe.
