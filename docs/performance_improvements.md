The performance review identified 11 categories of issues across the Ruby backend and TypeScript frontend. Here's a summary:
ð´ P0 - Critical:

1. Synchronous EventBus on tick hot path â single tick triggers cascading synchronous work (PnL, DB, Redis, broadcasts, risk eval) on the WebSocket reactor thread
2. Redis connection proliferation â 6+ separate Redis.new() connections across services, no pooling
ð  P1 - High:
3. Repeated PositionTracker.active queries bypassing cache (3-5 DB queries/sec)
4. Instrument.find_by_sid_and_segment per index tick (~4 queries/sec)
5. Regex numeric? on every tick field creating GC pressure
ð¡ P2 - Medium:
6. build_dashboard_stats doing heavy aggregation every 1s
7. Sequential WebSocket subscribe on reconnect (slow recovery)
8. Missing partial DB indexes on hot query patterns
ð¢ P3 - Low:
9. BigDecimal allocation in PnL hot path
10. rescue nil swallowing real errors
11. TypeScript: ActionCable subscription leaks, missing React.memo/useMemo, missing virtualization
All 11 findings are detailed in the task output above with file:line references and code snippets.
