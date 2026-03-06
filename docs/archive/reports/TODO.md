# TODO — Code Review Backlog (Ruby/Rails/Workers/Vite Dashboard)

_Last updated: 2026-03-04_

## Scope reviewed
- Rails API controllers and jobs under `app/controllers/api/` and `app/jobs/`.
- Dashboard frontend under `dashboard/src/` and Vite config in `dashboard/vite.config.js`.

## P0 — Reliability / Trading Safety
- [ ] Replace shelling out from `AiTechnicalAnalysisJob` (`system("bundle exec rake ...")`) with a service object invocation to avoid command injection/string escaping risks and to improve observability/testability.
  - Add explicit timeout + structured failure metrics.
  - Keep idempotency key per `index_name` + trading session.
- [ ] Remove long `sleep` calls from `SmcScannerJob` hot path and move scan-per-index to child jobs (`perform_later`) with queue throttling/rate-limiter.
  - Goal: avoid worker thread starvation and improve throughput.
- [ ] Add lock/idempotency strategy for scanner and AI-analysis jobs (e.g., Redis lock or unique jobs) so duplicate enqueues cannot execute same cycle twice.
- [ ] Replace broad `rescue StandardError` blocks in jobs with narrower error classes and central retry/discard policy in `ApplicationJob`.

## P1 — Rails API Best Practices
- [ ] Introduce API serializers/presenters for dashboard and positions responses to keep controllers thin and reduce duplicated number formatting logic.
- [ ] Add request-level error handling for non-2xx dashboard/positions responses; currently frontend assumes JSON success.
- [ ] Remove token fallback via query param in circuit-breaker endpoint; accept auth token only from headers.
- [ ] Add strict parameter validation schema for circuit-breaker `reason` and enforce max length.
- [ ] Add API contract/request specs for `/api/dashboard`, `/api/positions`, and `/api/circuit_breaker*` including unauthorized scenarios.

## P1 — Worker / Background Processing
- [ ] Configure explicit queue names/priorities and concurrency budget for trading-critical vs analytics jobs.
- [ ] Add instrumentation (ActiveSupport::Notifications/StatsD) around job runtime, retries, rate-limit events, and external call latency.
- [ ] Move Telegram notification send path to dedicated notification job with dedupe key and dead-letter strategy.
- [ ] Add tests for expiry filtering/date parsing edge-cases in `SmcScannerJob` (`Date.parse` behavior, invalid strings, empty expiry list).

## P2 — Ruby Code Quality
- [ ] Add YARD/RDoc to public methods in jobs/composables-facing API endpoints and core services.
- [ ] Extract repeated numeric rounding / pnl_pct calculations to a shared formatter/value object to avoid divergence between open/closed position serializers.
- [ ] Ensure money fields remain `BigDecimal` through calculation boundaries; avoid early `to_f` conversion before final presentation.
- [ ] Standardize structured logging payloads (JSON key-value) for easier production filtering and alerting.

## P1 — Vite / Dashboard Enhancements
- [ ] Add unified API client wrapper with:
  - abortable fetch,
  - retry/backoff for transient failures,
  - non-200 handling,
  - typed runtime guards for payload shape.
- [ ] Add connection state UX for ActionCable (`connecting/reconnecting/stale`) and show stale-data badge when last update exceeds threshold.
- [ ] Add auto-refresh pause when tab is hidden and resume on visibility change to reduce unnecessary polling load.
- [ ] Add dashboard-level error boundary/toast for failed API calls and cable disconnects.
- [ ] Add table virtualization for large closed-trades list and client-side filters (index, direction CE/PE, PnL band, time range).
- [ ] Add unit tests for `useDashboard`/`usePositions` (poll timer lifecycle, merge semantics for `pnl_update`, reconnect behavior).

## P2 — Security / Ops / Tooling
- [ ] Add Brakeman, bundler-audit, and RuboCop checks to CI (if missing) with failure thresholds.
- [ ] Add `.env.example` entries for dashboard-related envs and circuit-breaker token expectations.
- [ ] Add runbook doc section for worker recovery: queue drain strategy, retry storm handling, and safe PAPER_MODE toggles.

## Suggested execution order
1. P0 job safety/idempotency + remove blocking sleeps.
2. API hardening (auth + specs + serializers).
3. Dashboard reliability UX and client wrapper.
4. Worker instrumentation + CI security/lint gates.
