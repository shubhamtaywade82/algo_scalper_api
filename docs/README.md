# docs/

Living documentation for the algo_scalper_api codebase.

## Layout

| Path | Purpose |
|---|---|
| `architecture/` | System architecture diagrams and component overviews |
| `development/` | Developer guides: setup, deployment, contribution conventions |
| `operations/` | Runbooks, redis keys, observability, ops procedures |
| `runbooks/` | Step-by-step incident response procedures |
| `troubleshooting/` | Known issues and diagnostic playbooks |
| `guides/` | How-to guides for common tasks (DhanHQ client, websocket, configuration, usage) |
| `options/` | Options trading strategy research and design |
| `OPTIONS_RESEARCH/` | Long-form research notes on naked options buying |
| `superpowers/plans/` | Dated implementation plans (active and historical) |
| `FrontendImprovements/` | Dashboard frontend architecture and roadmap |
| `archive/` | Historical/superseded material — see [`archive/README.md`](./archive/README.md) |

## Canonical sources

When the same topic appears in both `docs/<top>/` and `docs/archive/<top>/`,
the live version under `docs/<top>/` is canonical. Archive copies are kept
for reference only and may be stale.

## Top-level files

- `COMPLETE_SYSTEM_FLOW.md` — end-to-end system walkthrough
- `AlgoScalperPlatform-v2.0.md` — platform overview
- `SMC_SETUP_GUIDE.md` — Smart Money Concepts setup
