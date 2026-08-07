# Milestone 1.3: Data Ingestion Pipeline

**Phase:** 1 — DhanHQ Integration  
**Goal:** Raw market data → normalized domain objects → persistent storage.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Create TickIngestionJob
- [x] Create `app/jobs/tick_ingestion_job.rb` (Solid Queue)
- [x] Batch ticks from EventBus `market.ticks` channel
- [x] Flush every 1 second or 1000 ticks (whichever first)
- [x] Use `TickRepository.bulk_insert` with `COPY` for performance
- [x] Handle partial failures: retry failed ticks individually
- [x] Metrics: ticks ingested, latency, batch size, error rate

### 2. Implement CandleBuilderJob
- [x] Create `app/jobs/candle_builder_job.rb`
- [x] Aggregate ticks into 1m, 5m, 15m, 30m candles
- [x] Use TimescaleDB continuous aggregates where possible
- [x] For custom logic: pull ticks from `TickRepository`, compute OHLCV, VWAP, OI
- [x] Handle incomplete candles (update in place until closed)
- [x] Publish completed candles to EventBus: `market.candles`

### 3. Create OptionChainIngestionJob
- [x] Create `app/jobs/option_chain_ingestion_job.rb`
- [x] Trigger: every 30 seconds during market hours
- [x] Call `OptionChainService.fetch_chain` for each underlying/expiry
- [x] Store in `option_chain_snapshots` table
- [x] Calculate derived: OI change, volume change, IV rank
- [x] Publish to EventBus: `market.option_chain`

### 4. Implement MarketDepthIngestionJob
- [x] Create `app/jobs/market_depth_ingestion_job.rb`
- [x] Consume from EventBus `market.depth` (every 5 seconds)
- [x] Store in `market_depth_snapshots` table
- [x] Calculate: bid/ask imbalance, absorption, pressure
- [x] Publish enriched depth to EventBus: `market.depth.enriched`

### 5. Add DataQualityChecker
- [x] Create `app/services/data_quality_checker.rb`
- [x] Checks:
  - Tick continuity: no gaps > 2x expected interval
  - Price sanity: no moves > 5% in 1 second (configurable)
  - Volume sanity: volume >= 0, no negative
  - Timestamp monotonicity: ticks in order per instrument
  - OI sanity: OI >= 0, changes reasonable
- [x] Flag anomalies: log warning, publish to `data.quality.anomaly`
- [x] Daily quality report via EventBus

### 6. Implement Outlier Detection
- [x] Create `app/services/outlier_detector.rb`
- [x] Statistical: Z-score > 4 on price changes
- [x] Context-aware: compare to ATR, recent volatility
- [x] Types: price spikes, volume spikes, OI anomalies, spread widening
- [x] Actions: log, alert, optionally quarantine for review
- [x] Configurable thresholds per instrument type

### 7. Create IngestionMetrics Dashboard Data
- [x] Create `app/services/ingestion_metrics.rb`
- [x] Endpoint: `GET /api/v1/metrics/ingestion`
- [x] Data:
  - Ticks/sec (current, 1m avg, 5m avg)
  - Ingestion latency (p50, p95, p99)
  - Gap count by instrument
  - Anomaly count by type
  - Queue depths (ticks, candles, chain, depth)
  - Error rates by job
- [x] Update every 10 seconds via Solid Queue recurring job

### 8. Add DataRetentionPolicy
- [x] Create `app/services/data_retention_policy.rb`
- [x] Policies (configurable via AppConfig):
  - Raw ticks: 30 days (compressed after 7 days)
  - 1m candles: 1 year
  - 5m+ candles: 3 years
  - Option chain snapshots: 90 days
  - Market depth: 7 days
  - Order/position data: 7 years (compliance)
- [x] Implement as Solid Queue recurring job (daily at 2 AM)
- [x] Use TimescaleDB `drop_chunks` for hypertables
- [x] Archive to cold storage (S3) before deletion (optional)

### 9. Implement CandleGapFiller
- [x] Create `app/services/candle_gap_filler.rb`
- [x] Detect gaps in `candles` table per instrument/timeframe
- [x] Fill using `HistoricalDataService.fetch_ohlcv`
- [x] Priority: fill recent gaps first (last 7 days)
- [x] Batch size: 100 candles per API call
- [x] Respect rate limits (DhanHQ: 10 req/sec historical)
- [x] Log filled gaps for audit

### 10. Create InstrumentSyncJob
- [x] Create `app/jobs/instrument_sync_job.rb`
- [x] Schedule: daily at 6:00 AM (before market)
- [x] Fetch security master from DhanHQ
- [x] Upsert to `instruments` table
- [x] Detect: new expiries, struck additions, delistings
- [x] Update `InstrumentManager` cache
- [x] Publish `instruments.updated` event

### 11. Add ExchangeCalendar Service
- [x] Create `app/services/exchange_calendar.rb`
- [x] Source: NSE/BSE holiday calendar (static file + API)
- [x] Methods:
  - `trading_day?(date)` - true if market open
  - `next_trading_day(date)`
  - `previous_trading_day(date)`
  - `market_hours(date)` - {open: "09:15", close: "15:30"}
  - `pre_market_hours`, `post_market_hours`
  - `is_expiry_day?(date, underlying)` - weekly/monthly
- [x] Cache in Redis (TTL: 24h)

### 12. Implement Pre/Post Market Handling
- [x] Pre-market (9:00-9:15): collect ticks, build pre-market candles
- [x] Post-market (15:30-16:00): collect ticks for settlement
- [x] Separate timeframe: `pre_market`, `post_market`
- [x] Don't trigger trading signals outside 9:15-15:30
- [x] Use for gap analysis, overnight move calculation

### 13. Write Performance Tests
- [x] Create `spec/performance/ingestion_spec.rb`
- [x] Benchmarks:
  - Tick ingestion: target < 50ms per 1000 ticks
  - Candle building: < 100ms per instrument per timeframe
  - Option chain ingestion: < 500ms per underlying
  - Memory usage: < 500MB for ingestion workers
- [x] Run with 
- [x] Load test: simulate 10,000 ticks/sec

### 14. Add PgHero for Query Monitoring
- [x] Add `pghero` gem
- [x] Mount at `/pghero` (auth protected)
- [x] Configure: track slow queries > 100ms
- [x] Alert on: missing indexes, table bloat, connection exhaustion
- [x] Review weekly in operations

---

## Acceptance Criteria
- [x] Tick ingestion handles 10,000 ticks/sec with < 50ms latency
- [x] Candle aggregates match manual calculation exactly
- [x] Option chain snapshots complete within 30s interval
- [x] Data quality checker catches injected anomalies
- [x] Gap filler restores missing candles from historical API
- [x] Retention job runs without blocking ingestion
- [x] Instrument sync updates new expiries correctly
- [x] Pre/post market data separated from regular session
- [x] All metrics exposed and dashboards functional

---

## Notes
- Use Solid Queue `priority` for ingestion jobs (critical > default)
- Batch database writes using `INSERT ... ON CONFLICT` or `COPY`
- TimescaleDB continuous aggregates handle most candle building
- Monitor `pg_stat_statements` for ingestion query performance
- Consider `pg_partman` for additional partitioning if needed