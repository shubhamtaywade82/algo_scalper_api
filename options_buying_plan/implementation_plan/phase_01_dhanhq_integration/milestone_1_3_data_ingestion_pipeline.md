# Milestone 1.3: Data Ingestion Pipeline

**Phase:** 1 — DhanHQ Integration  
**Goal:** Raw market data → normalized domain objects → persistent storage.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Create TickIngestionJob
- [ ] Create `app/jobs/tick_ingestion_job.rb` (Solid Queue)
- [ ] Batch ticks from EventBus `market.ticks` channel
- [ ] Flush every 1 second or 1000 ticks (whichever first)
- [ ] Use `TickRepository.bulk_insert` with `COPY` for performance
- [ ] Handle partial failures: retry failed ticks individually
- [ ] Metrics: ticks ingested, latency, batch size, error rate

### 2. Implement CandleBuilderJob
- [ ] Create `app/jobs/candle_builder_job.rb`
- [ ] Aggregate ticks into 1m, 5m, 15m, 30m candles
- [ ] Use TimescaleDB continuous aggregates where possible
- [ ] For custom logic: pull ticks from `TickRepository`, compute OHLCV, VWAP, OI
- [ ] Handle incomplete candles (update in place until closed)
- [ ] Publish completed candles to EventBus: `market.candles`

### 3. Create OptionChainIngestionJob
- [ ] Create `app/jobs/option_chain_ingestion_job.rb`
- [ ] Trigger: every 30 seconds during market hours
- [ ] Call `OptionChainService.fetch_chain` for each underlying/expiry
- [ ] Store in `option_chain_snapshots` table
- [ ] Calculate derived: OI change, volume change, IV rank
- [ ] Publish to EventBus: `market.option_chain`

### 4. Implement MarketDepthIngestionJob
- [ ] Create `app/jobs/market_depth_ingestion_job.rb`
- [ ] Consume from EventBus `market.depth` (every 5 seconds)
- [ ] Store in `market_depth_snapshots` table
- [ ] Calculate: bid/ask imbalance, absorption, pressure
- [ ] Publish enriched depth to EventBus: `market.depth.enriched`

### 5. Add DataQualityChecker
- [ ] Create `app/services/data_quality_checker.rb`
- [ ] Checks:
  - Tick continuity: no gaps > 2x expected interval
  - Price sanity: no moves > 5% in 1 second (configurable)
  - Volume sanity: volume >= 0, no negative
  - Timestamp monotonicity: ticks in order per instrument
  - OI sanity: OI >= 0, changes reasonable
- [ ] Flag anomalies: log warning, publish to `data.quality.anomaly`
- [ ] Daily quality report via EventBus

### 6. Implement Outlier Detection
- [ ] Create `app/services/outlier_detector.rb`
- [ ] Statistical: Z-score > 4 on price changes
- [ ] Context-aware: compare to ATR, recent volatility
- [ ] Types: price spikes, volume spikes, OI anomalies, spread widening
- [ ] Actions: log, alert, optionally quarantine for review
- [ ] Configurable thresholds per instrument type

### 7. Create IngestionMetrics Dashboard Data
- [ ] Create `app/services/ingestion_metrics.rb`
- [ ] Endpoint: `GET /api/v1/metrics/ingestion`
- [ ] Data:
  - Ticks/sec (current, 1m avg, 5m avg)
  - Ingestion latency (p50, p95, p99)
  - Gap count by instrument
  - Anomaly count by type
  - Queue depths (ticks, candles, chain, depth)
  - Error rates by job
- [ ] Update every 10 seconds via Solid Queue recurring job

### 8. Add DataRetentionPolicy
- [ ] Create `app/services/data_retention_policy.rb`
- [ ] Policies (configurable via AppConfig):
  - Raw ticks: 30 days (compressed after 7 days)
  - 1m candles: 1 year
  - 5m+ candles: 3 years
  - Option chain snapshots: 90 days
  - Market depth: 7 days
  - Order/position data: 7 years (compliance)
- [ ] Implement as Solid Queue recurring job (daily at 2 AM)
- [ ] Use TimescaleDB `drop_chunks` for hypertables
- [ ] Archive to cold storage (S3) before deletion (optional)

### 9. Implement CandleGapFiller
- [ ] Create `app/services/candle_gap_filler.rb`
- [ ] Detect gaps in `candles` table per instrument/timeframe
- [ ] Fill using `HistoricalDataService.fetch_ohlcv`
- [ ] Priority: fill recent gaps first (last 7 days)
- [ ] Batch size: 100 candles per API call
- [ ] Respect rate limits (DhanHQ: 10 req/sec historical)
- [ ] Log filled gaps for audit

### 10. Create InstrumentSyncJob
- [ ] Create `app/jobs/instrument_sync_job.rb`
- [ ] Schedule: daily at 6:00 AM (before market)
- [ ] Fetch security master from DhanHQ
- [ ] Upsert to `instruments` table
- [ ] Detect: new expiries, struck additions, delistings
- [ ] Update `InstrumentManager` cache
- [ ] Publish `instruments.updated` event

### 11. Add ExchangeCalendar Service
- [ ] Create `app/services/exchange_calendar.rb`
- [ ] Source: NSE/BSE holiday calendar (static file + API)
- [ ] Methods:
  - `trading_day?(date)` - true if market open
  - `next_trading_day(date)`
  - `previous_trading_day(date)`
  - `market_hours(date)` - {open: "09:15", close: "15:30"}
  - `pre_market_hours`, `post_market_hours`
  - `is_expiry_day?(date, underlying)` - weekly/monthly
- [ ] Cache in Redis (TTL: 24h)

### 12. Implement Pre/Post Market Handling
- [ ] Pre-market (9:00-9:15): collect ticks, build pre-market candles
- [ ] Post-market (15:30-16:00): collect ticks for settlement
- [ ] Separate timeframe: `pre_market`, `post_market`
- [ ] Don't trigger trading signals outside 9:15-15:30
- [ ] Use for gap analysis, overnight move calculation

### 13. Write Performance Tests
- [ ] Create `spec/performance/ingestion_spec.rb`
- [ ] Benchmarks:
  - Tick ingestion: target < 50ms per 1000 ticks
  - Candle building: < 100ms per instrument per timeframe
  - Option chain ingestion: < 500ms per underlying
  - Memory usage: < 500MB for ingestion workers
- [ ] Run with 
- [ ] Load test: simulate 10,000 ticks/sec

### 14. Add PgHero for Query Monitoring
- [ ] Add `pghero` gem
- [ ] Mount at `/pghero` (auth protected)
- [ ] Configure: track slow queries > 100ms
- [ ] Alert on: missing indexes, table bloat, connection exhaustion
- [ ] Review weekly in operations

---

## Acceptance Criteria
- [ ] Tick ingestion handles 10,000 ticks/sec with < 50ms latency
- [ ] Candle aggregates match manual calculation exactly
- [ ] Option chain snapshots complete within 30s interval
- [ ] Data quality checker catches injected anomalies
- [ ] Gap filler restores missing candles from historical API
- [ ] Retention job runs without blocking ingestion
- [ ] Instrument sync updates new expiries correctly
- [ ] Pre/post market data separated from regular session
- [ ] All metrics exposed and dashboards functional

---

## Notes
- Use Solid Queue `priority` for ingestion jobs (critical > default)
- Batch database writes using `INSERT ... ON CONFLICT` or `COPY`
- TimescaleDB continuous aggregates handle most candle building
- Monitor `pg_stat_statements` for ingestion query performance
- Consider `pg_partman` for additional partitioning if needed