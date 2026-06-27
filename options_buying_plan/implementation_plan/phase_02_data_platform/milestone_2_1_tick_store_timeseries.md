# Milestone 2.1: Tick Store & Time-Series Database

**Phase:** 2 — Data Platform  
**Goal:** High-performance tick storage with TimescaleDB.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Install and Configure TimescaleDB Extension
- [ ] Enable `timescaledb` extension in PostgreSQL: `CREATE EXTENSION IF NOT EXISTS timescaledb;`
- [ ] Verify version compatibility with PostgreSQL 16+
- [ ] Configure `timescaledb.max_background_workers` in `postgresql.conf`
- [ ] Run `timescaledb_pre_restore.sh` if restoring from backup

### 2. Convert Market_Ticks to Hypertable
- [ ] Migration: `SELECT create_hypertable('market_ticks', 'timestamp', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);`
- [ ] Set `compress_segmentby = 'instrument_id'` for compression
- [ ] Verify chunk creation: `SELECT * FROM timescaledb_information.chunks WHERE hypertable_name = 'market_ticks';`

### 3. Create Continuous Aggregates for Candles
- [ ] 1-minute aggregate:
  ```sql
  CREATE MATERIALIZED VIEW candles_1m
  WITH (timescaledb.continuous) AS
  SELECT instrument_id,
         time_bucket('1 minute', timestamp) AS bucket,
         FIRST(price, timestamp) AS open,
         MAX(price) AS high,
         MIN(price) AS low,
         LAST(price, timestamp) AS close,
         SUM(volume) AS volume,
         LAST(oi, timestamp) AS oi,
         SUM(price * volume) / NULLIF(SUM(volume), 0) AS vwap,
         COUNT(*) AS trade_count
  FROM market_ticks
  GROUP BY instrument_id, bucket;
  ```
- [ ] Repeat for 5m, 15m, 30m, 1h, 1d with appropriate bucket intervals
- [ ] Add indexes on each continuous aggregate: `CREATE INDEX ON candles_1m (instrument_id, bucket DESC);`

### 4. Implement Compression Policy
- [ ] Enable compression: `ALTER TABLE market_ticks SET (timescaledb.compress, timescaledb.compress_segmentby = 'instrument_id');`
- [ ] Add compression policy: `SELECT add_compression_policy('market_ticks', INTERVAL '7 days');`
- [ ] Verify compression ratio: `SELECT * FROM timescaledb_information.compression_stats;`

### 5. Add Retention Policies
- [ ] Raw ticks retention (30 days): `SELECT add_retention_policy('market_ticks', INTERVAL '30 days');`
- [ ] 1m candles retention (1 year): `SELECT add_retention_policy('candles_1m', INTERVAL '1 year');`
- [ ] Higher timeframes: 5m (2 years), 15m (5 years), 1h/d (indefinite)

### 6. Create TickQueryService
- [ ] Create `app/services/engines/tick_query_service.rb`
- [ ] Methods:
  - `ticks(instrument_id, from:, to:, limit:)` - raw tick queries
  - `ticks_by_range(instrument_id, range)` - convenience (1h, 1d, 1w)
  - `latest_tick(instrument_id)` - most recent tick
  - `tick_count(instrument_id, from:, to:)` - for gap detection
- [ ] Use hypertable partitioning for automatic partition pruning

### 7. Implement TickReplayService
- [ ] Create `app/services/engines/tick_replay_service.rb`
- [ ] Method: `replay(instrument_id, from:, to:, speed: 1.0, &block)`
- [ ] Yield ticks in timestamp order with configurable speed multiplier
- [ ] Support pause/resume/seek for backtesting UI
- [ ] Batch fetch from TimescaleDB (1000 ticks per query)

### 8. Add COPY-Based Bulk Import
- [ ] Create `app/services/engines/tick_bulk_import_service.rb`
- [ ] Method: `import_csv(file_path, instrument_id)` using `COPY market_ticks (...) FROM STDIN`
- [ ] Handle timestamp parsing, invalid rows, duplicates
- [ ] Progress reporting via callback
- [ ] Use for historical data seeding

### 9. Create Indexes on All Time-Series Tables
- [ ] `market_ticks`: `(instrument_id, timestamp DESC)` (auto from hypertable)
- [ ] `candles_*`: `(instrument_id, bucket DESC)`
- [ ] `option_chain_snapshots`: `(instrument_id, snapshot_time DESC, strike, option_type)`
- [ ] `market_depth_snapshots`: `(instrument_id, timestamp DESC)`
- [ ] `market_regimes`: `(instrument_id, timeframe, detected_at DESC)`
- [ ] `market_structures`: `(instrument_id, timeframe, timestamp DESC)`

### 10. Benchmark Tick Ingestion
- [ ] Create benchmark script: `scripts/benchmark_tick_ingestion.rb`
- [ ] Target: 10,000 ticks/second sustained
- [ ] Measure: insert latency (p50, p95, p99), CPU, memory, disk I/O
- [ ] Test with: single instrument, 10 instruments, 100 instruments
- [ ] Document results in `docs/benchmarks/tick_ingestion.md`

### 11. Add pg_stat_statements Tracking
- [ ] Enable extension: `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`
- [ ] Configure `pg_stat_statements.track = all` in postgresql.conf
- [ ] Create query performance dashboard queries
- [ ] Set up alerts for: query time > 1s, rows scanned > 1M

### 12. Document Schema
- [ ] Create `docs/database/schema.md` with:
  - ERD diagram (Mermaid.js)
  - Table definitions with column types
  - Index list with rationale
  - Hypertable/continuous aggregate configuration
  - Retention/compression policies
  - Query patterns and optimization notes

---

## Acceptance Criteria
- [ ] TimescaleDB extension installed and configured
- [ ] `market_ticks` is a hypertable with 1-day chunks
- [ ] Continuous aggregates exist for all required timeframes
- [ ] Compression reduces raw tick storage by >90% after 7 days
- [ ] Retention policies automatically drop old data
- [ ] `TickQueryService` returns correct data for all query patterns
- [ ] `TickReplayService` replays 1M ticks in < 30s at 100x speed
- [ ] Bulk import loads 10M ticks in < 5 minutes
- [ ] All time-series queries use partition pruning (EXPLAIN shows chunk exclusion)
- [ ] Benchmark meets 10k ticks/sec target
- [ ] `pg_stat_statements` shows no full-table scans on time-series queries

---

## Notes
- Run `ANALYZE` after bulk loads for query planner statistics
- Consider `timescaledb.parallel_chunk_scan` for large scans
- Use `time_bucket_gapfill` for gap-filled candle queries
- Monitor chunk count; too many chunks hurts performance
- Background workers handle compression/retention automatically