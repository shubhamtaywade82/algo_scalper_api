# Algo Scalper API Review

## Current Integration Snapshot
- The repository already wraps the `DhanHQ` gem inside `Dhanhq::Client`, exposing helpers for orders, positions, holdings, historical data, and account profile access with consistent error handling and an environment guard.【F:app/services/dhanhq/client.rb†L1-L154】
- Live streaming utilities exist for both market data (`Live::MarketFeedSupervisor`) and order updates (`Live::OrderUpdateHub`), each wiring ActiveSupport notifications and callback registration on top of the WebSocket clients, plus a simple in-memory tick cache for consumers.【F:app/services/live/market_feed_supervisor.rb†L1-L139】【F:app/services/live/order_update_hub.rb†L1-L88】【F:app/services/live/tick_cache.rb†L1-L33】
- Initializers bootstrap the DhanHQ client based on environment flags and automatically start or stop the streaming supervisors when the integration is enabled.【F:config/initializers/dhanhq.rb†L1-L56】【F:config/initializers/dhanhq_streams.rb†L1-L31】
- Documentation from the upstream `dhanhq-client` repository is already vendored, outlining the breadth of REST and WebSocket features available to the API layer here.【F:docs/dhanhq-client.md†L1-L200】

## Missing Building Blocks
- There are no public API routes beyond the default `/up` health probe, so none of the DhanHQ capabilities are currently reachable over HTTP.【F:config/routes.rb†L1-L10】
- The project lacks domain models, migrations, and persistence strategy—`db/migrate` is absent—so we cannot store strategies, execution logs, or state required by a scalping engine.【7692b9†L1-L2】
- Background processing is unimplemented: aside from the generated `ApplicationJob`, there are no Solid Queue jobs coordinating polling, order lifecycle orchestration, or recovery flows.【F:app/jobs/application_job.rb†L1-L7】
- Automated tests are missing entirely (`test/` is not present), leaving the integration points with the trading client and live feeds unverified.【19c025†L1-L2】
- The README still contains the Rails scaffold placeholders and omits setup, seeding, and operational runbooks for this service.【F:README.md†L1-L35】

## Recommendations (Leveraging the `dhanhq-client` Repo)
- Surface the REST features (orders, positions, holdings, funds, historical data, option chain) through API controllers that delegate to `Dhanhq.client`, mirroring the operations documented in the client guide so other services can consume them programmatically.【F:docs/dhanhq-client.md†L5-L134】【F:app/services/dhanhq/client.rb†L25-L109】
- Introduce persistence for strategies, executions, and tick snapshots via migrations plus Active Record models, enabling the API to correlate WebSocket events with stored strategy state.
- Add Solid Queue jobs for routine housekeeping—such as refreshing positions after order placement or backfilling historical candles—so we exploit the background infrastructure already declared in the Gemfile.
- Establish request specs and service tests that stub the `DhanHQ` gem, validating success/error paths described in the guide and guarding regressions in our wrappers.【F:docs/dhanhq-client.md†L94-L200】
- Replace the placeholder README with concrete setup instructions (environment variables, queue/cache requirements, how to boot live feeds) referencing the configuration knobs already supported by the initializers and the upstream documentation.【F:config/initializers/dhanhq.rb†L9-L48】【F:docs/dhanhq-client.md†L15-L27】
