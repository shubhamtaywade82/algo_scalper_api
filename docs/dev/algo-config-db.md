# Algo Config — DB-First Operations

Runtime trading config is **DB-canonical**. YAML files seed the database at bootstrap; edits to
`config/algo.yml` do not apply until you re-bootstrap.

## Resolution Order

`AlgoConfig.fetch` (30s cache) builds effective config:

1. `settings.algo_config_document` — full trading config snapshot
2. `settings.signal_tier_presets` — tier overlay (`exploratory` | `standard` | `selective`)
3. `settings.india_index_registry` — index identity merge into `indices[]`
4. `LIVE_TRADING` env — forces paper vs live gateway
5. `SIGNAL_TIER_FORCE=true` + `SIGNAL_TIER` env — emergency tier override only

Credential sections (`dhanhq`, `telegram`, `ai`) are excluded from API writes and position
snapshots.

## Bootstrap (new environment)

```bash
FORCE=1 bundle exec rake algo_config:bootstrap_document
bundle exec rake algo_config:bootstrap_auxiliary
bundle exec rake algo_config:migrate_legacy_overrides
bundle exec rake algo_config:verify_canonical
```

Restart the trading daemon after code deploys. DB-only changes propagate within **~1 second** via
Redis pub/sub (`algo_config:invalidate`); without Redis, allow up to 30 seconds for
`AlgoConfig.fetch` cache TTL.

## Calibration Loop

Closed-trade / historical optimizers propose patches as pending `calibration_runs` records.
Apply via API after review:

```bash
GET  /api/calibration_runs
POST /api/calibration_runs/:id/apply   # requires X-Settings-Update-Token when set
```

Trailing optimizer (proposes, does not auto-apply by default):

```bash
bundle exec rake optimize:trailing
APPLY=1 bundle exec rake optimize:trailing   # auto-apply after propose
```

## Audit

```bash
bundle exec rake algo_config:audit
bundle exec rake algo_config:verify_canonical
```

## Runtime Updates

- **API:** `PATCH /api/settings/bulk` (replace top-level subtree) or `PATCH /api/settings/deep_merge`
- **Dashboard:** Settings page writes to `algo_config_document`
- **Audit trail:** `GET /api/settings/change_logs`

## Apply YAML Changes

After editing `config/algo.yml`, `config/signal_tier_presets.yml`, or
`config/india_index_registry.yml`:

```bash
FORCE=1 bundle exec rake algo_config:bootstrap_document   # main config
FORCE=1 bundle exec rake algo_config:bootstrap_auxiliary  # tier + registry
```

Review diff first with `bundle exec rake algo_config:audit`.

## Rollback

Use `AlgoConfigChangeLog` rows to inspect prior patches. Re-apply a known-good document via
API bulk replace or re-run bootstrap from a git revision.
