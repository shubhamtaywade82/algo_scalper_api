# Milestone 2.1: Tick Store & Time-Series Database

**Phase:** 2 — Data Platform  
**Goal:** High-performance tick storage with TimescaleDB.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Install and Configure TimescaleDB Extension
- [x] Enable `timescaledb` extension in PostgreSQL: `CREATE EXTENSION IF NOT EXISTS timescaledb;`
- [x] Verify version compatibility with PostgreSQL 16+
- [x] Configure `timescaledb.max_background_workers` in `postgresql.conf`
- [x] Run `timescaledb_pre_restore.sh` if restoring from backup

### 2. Convert Market_Ticks to Hypertable
- [x] Migration: `SELECT create_hypertable('market_ticks', 'timestamp', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);`
- [x] Set `compress_segmentby = 'instrument_id'` for compression
- [x] Verify chunk creation: `SELECT * FROM timescaledb_information.chunks WHERE hypertable_name = 'market_ticks';`

### 3. Create Continuous Aggregates for Candles
- [x] 1-minute aggregate:
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
- [x] Repeat for 5m, 15m, 30m, 1h, 1d with appropriate bucket intervals
- [x] Add indexes on each continuous aggregate: `CREATE INDEX ON candles_1m (instrument_id, bucket DESC);`

### 4. Implement Compression Policy
- [x] Enable compression: `ALTER TABLE market_ticks SET (timescaledb.compress, timescaledb.compress_segmentby = 'instrument_id');`
- [x] Add compression policy: `SELECT add_compression_policy('market_ticks', INTERVAL '7 days');`
- [x] Verify compression ratio: `SELECT * FROM timescaledb_information.compression_stats;`

### 5. Add Retention Policies
- [x] Raw ticks retention (30 days): `SELECT add_retention_policy('market_ticks', INTERVAL '30 days');`
- [x] 1m candles retention (1 year): `SELECT add_retention_policy('candles_1m', INTERVAL '1 year');`
- [x] Higher timeframes: 5m (2 years), 15m (5 years), 1h/d (indefinite)

### 6. Create TickQueryService
- [x] Create `app/services/engines/tick_query_service.rb`
- [x] Methods:
  - `ticks(instrument_id, from:, to:, limit:)` - raw tick queries
  - `ticks_by_range(instrument_id, range)` - convenience (1h, 1d, 1w)
  - `latest_tick(instrument_id)` - most recent tick
  - `tick_count(instrument_id, from:, to:)` - for gap detection
- [x] Use hypertable partitioning for automatic partition pruning

### 7. Implement TickReplayService
- [x] Create `app/services/engines/tick_replay_service.rb`
- [x] Method: `replay(instrument_id, from:, to:, speed: 1.0, &block)`
- [x] Yield ticks in timestamp order with configurable speed multiplier
- [x] Support pause/resume/seek for backtesting UI
- [x] Batch fetch from TimescaleDB (1000 ticks per query)

### 8. Add COPY-Based Bulk Import
- [x] Create `app/services/engines/tick_bulk_import_service.rb`
- [x] Method: `import_csv(file_path, instrument_id)` using `COPY market_ticks (...) FROM STDIN`
- [x] Handle timestamp parsing, invalid rows, duplicates
- [x] Progress reporting via callback
- [x] Use for historical data seeding

### 9. Create Indexes on All Time-Series Tables
- [x] `market_ticks`: `(instrument_id, timestamp DESC)` (auto from hypertable)
- [x] `candles_*`: `(instrument_id, bucket DESC)`
- [x] `option_chain_snapshots`: `(instrument_id, snapshot_time DESC, strike, option_type)`
- [x] `market_depth_snapshots`: `(instrument_id, timestamp DESC)`
- [x] `market_regimes`: `(instrument_id, timeframe, detected_at DESC)`
- [x] `market_structures`: `(instrument_id, timeframe, timestamp DESC)`

### 10. Benchmark Tick Ingestion
- [x] Create benchmark script: `scripts/benchmark_tick_ingestion.rb`
- [x] Target: 10,000 ticks/second sustained
- [x] Measure: insert latency (p50, p95, p99), CPU, memory, disk I/O
- [x] Test with: single instrument, 10 instruments, 100 instruments
- [x] Document results in `docs/benchmarks/tick_ingestion.md`

### 11. Add pg_stat_statements Tracking
- [x] Enable extension: `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`
- [x] Configure `pg_stat_statements.track = all` in postgresql.conf
- [x] Create query performance dashboard queries
- [x] Set up alerts for: query time > 1s, rows scanned > 1M

### 12. Document Schema
- [x] Create `docs/database/schema.md` with:
  - ERD diagram (Mermaid.js)
  - Table definitions with column types
  - Index list with rationale
  - Hypertable/continuous aggregate configuration
  - Retention/compression policies
  - Query patterns and optimization notes

---

## Acceptance Criteria
- [x] TimescaleDB extension installed and configured
- [x] `market_ticks` is a hypertable with 1-day chunks
- [x] Continuous aggregates exist for all required timeframes
- [x] Compression reduces raw tick storage by >90% after 7 days
- [x] Retention policies automatically drop old data
- [x] `TickQueryService` returns correct data for all query patterns
- [x] `TickReplayService` replays 1M ticks in < 30s at 100x speed
- [x] Bulk import loads 10M ticks in < 5 minutes
- [x] All time-series queries use partition pruning (EXPLAIN shows chunk exclusion)
- [x] Benchmark meets 10k ticks/sec target
- [x] `pg_stat_statements` shows no full-table scans on time-series queries

---

## Notes
- Run `ANALYZE` after bulk loads for query planner statistics
- Consider `timescaledb.parallel_chunk_scan` for large scans
- Use `time_bucket_gapfill` for gap-filled candle queries
- Monitor chunk count; too many chunks hurts performance
- Background workers handle compression/retention automatically