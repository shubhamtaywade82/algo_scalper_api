# Algo Config Settings: Versioning and Performance Tracking (Enhancements)

**Status:** Documented for implementation on a **new branch**. Not in scope for current branch.

**Full plan:** `.cursor/plans/Algo Config Settings Page with Versioning and Perf-87dd0131.plan.md`

---

## Goal

- Change algo config at runtime (already supported via Settings UI + `algo_config_overrides`; daemon picks up within ~30s).
- **Version** config: save current overrides as named snapshots, list versions, "Apply" a version to make it active.
- **Performance per version**: attribute positions to the active config version and aggregate PnL/stats per version (forward-test / strategy comparison).

---

## Enhancements to cover in new branch

| # | Enhancement | Scope |
|---|-------------|--------|
| 1 | Config versioning table and model | Backend: `algo_config_versions` table, `AlgoConfigVersion` model, `AlgoConfigVersion.current` |
| 2 | Position attribution to config version | Backend: `config_version_id` on `position_trackers`, set on create in EntryGuard / PositionSyncService |
| 3 | Config versions API | Backend: `Api::ConfigVersionsController` (index, create, show, apply, performance) + routes |
| 4 | Settings UI: Save as version, version list, Apply | Frontend: `dashboard/src/views/Settings.vue` |
| 5 | Per-version performance in UI | Frontend: display realized PnL, trade count, winners/losers per version |
| 6 | Optional: expand permitted settings keys | Backend: `PERMITTED_SETTINGS_KEYS` + document excluded keys |
| 7 | Optional: immediate config refresh after Apply | Backend: Redis/daemon cache bust so daemon sees change without 30s wait |

---

## Implementation order (when starting the branch)

1. Migrations: `algo_config_versions` table; add `config_version_id` to `position_trackers` with FK.
2. Model `AlgoConfigVersion` and `AlgoConfigVersion.current`.
3. Wire `config_version_id` into all `PositionTracker.create!` call sites.
4. `Api::ConfigVersionsController` + routes.
5. Settings.vue: "Save as version", version list, Apply, performance display.
6. (Optional) Expand `PERMITTED_SETTINGS_KEYS` and document excluded keys.
