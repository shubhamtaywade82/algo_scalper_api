# Milestone 0.3: Domain Model & Database Schema
**Sprint Duration:** 10 working days (2 weeks)
**Developer Capacity:** 1 full-time senior engineer
**Deliverable:** Core domain entities that all engines will consume and produce, with TimescaleDB optimization for market data.

---



## Day 19 — Schema Design & Foundation Tables

### Task 19.1: Initialize Schema Design Workshop
- **Context:** Begin Milestone 0.3 by locking the schema design before any migration is run.
- **Deliverable:** A clear schema design document and decision log for all tables.
- **Acceptance Criteria:**
  - Each table's purpose is documented before migration
  - No migration is generated until table contract is reviewed
  - Naming conventions and indexing approach are frozen

### Task 19.2: Create Instruments Table (Migration 1)
- **Migration:** `rails g migration CreateInstruments`
- **Columns:** `exchange_segment` (string, indexed), `security_id` (string, unique, indexed), `trading_symbol` (string, indexed), `expiry` (date, indexed), `strike` (decimal, indexed), `option_type` (string), `instrument_type` (string), `lot_size` (integer), `tick_size` (decimal), `underlying_symbol` (string, indexed), `is_active` (boolean, default true), `metadata` (jsonb)
- **Indexes:** composite `[:exchange_segment, :security_id]` and `[:underlying_symbol, :expiry, :option_type, :strike]`
- **Deliverable:** Instruments table created with appropriate indexes.
- **Acceptance Criteria:**
  - `bin/rails db:migrate` succeeds
  - `db/schema.rb` shows indexes exactly as designed
  - Schema matches Day 1 app structure

### Task 19.3: Create Market Ticks Table (Migration 2)
- **Migration:** `rails g migration CreateMarketTicks`
- **Columns:** `instrument_id` (bigint, foreign key), `timestamp` (timestamptz), `price` (decimal), `volume` (bigint), `bid_price`, `ask_price`, `bid_size`, `ask_size`, `oi` (open interest), `metadata` (jsonb)
- **TimescaleDB:** Convert to hypertable with 1-day chunks; compression and policies as designed.
- **Deliverable:** Market data table optimized for time-series ingestion.
- **Acceptance Criteria:**
  - `SELECT create_hypertable('market_ticks', 'timestamp', chunk_time_interval => INTERVAL '1 day')` runs post-migrate
  - Compression policy scheduled for older chunks
- **Commit:** `feat: create instruments + market_ticks tables`

---



## Day 20 — Market Data Tables (Continued)

### Task 20.1: Create Candles Table (Migration 3)
- **Migration:** `rails g migration CreateCandles`
- **Columns:** `instrument_id` (FK), `timeframe` (string), `timestamp` (timestamptz), `open`, `high`, `low`, `close`, `volume`, `oi`, `vwap`, `trade_count`, `metadata` (jsonb)
- **TimescaleDB:** Hypertable with 1-day chunks; unique constraint on `[:instrument_id, :timeframe, :timestamp]`.
- **Deliverable:** Candle data upsert-capable table for multi-timeframe strategies.

### Task 20.2: Create Option Chain Snapshots Table (Migration 4)
- **Migration:** `rails g migration CreateOptionChainSnapshots`
- **Columns:** `instrument_id`, `snapshot_time`, `strike`, `expiry`, `option_type`, `ce_oi`, `pe_oi`, `ce_volume`, `pe_volume`, `iv`, `delta`, `gamma`, `theta`, `vega`, `bid`, `ask`, `spread`, `ltp`, `metadata`
- **Deliverable:** Time-series table for option chain snapshots.
- **Acceptance Criteria:**
  - Composite index on `[:instrument_id, :snapshot_time DESC, :strike, :option_type]`
  - Tests ensure Greeks and volume columns are queryable

### Task 20.3: Create Market Depth Snapshots Table (Migration 5)
- **Migration:** `rails g migration CreateMarketDepthSnapshots`
- **Columns:** `instrument_id`, `timestamp`, `bid_levels` (jsonb), `ask_levels` (jsonb), `bid_imbalance`, `ask_imbalance`, `total_bid_volume`, `total_ask_volume`, `spread`, `mid_price`, `metadata`
- **Deliverable:** Snake-case JSONB depth snapshots for microstructure logic.

---



## Day 21 — Market Structure & Trade Setup Tables

### Task 21.1: Create Market Structures Table (Migration 6)
- **Columns:** `instrument_id`, `timeframe`, `structure_type` (HH/HL/LH/LL/BOS/CHOCH/FVG/OB), `price_level`, `timestamp`, `confirmed_at`, `is_active`, `strength`, `metadata`
- **Indexes:** `[:instrument_id, :timeframe, :timestamp DESC]`
- **Deliverable:** Market structure state machine persistence.

### Task 21.2: Create Market Regimes Table (Migration 7)
- **Columns:** `instrument_id`, `timeframe`, `regime_type`, `regime_score`, `adx_value`, `atr_value`, `ema_alignment`, `detected_at`, `valid_until`, `metadata`
- **Deliverable:** Regime classification history for engines.
- **Commit:** `feat: create market structures + regimes tables`

### Task 21.3: Create Trade Setups Table (Migration 8)
- **Columns:** `instrument_id`, `setup_type`, `direction`, `confidence`, `entry_price`, `stop_loss`, `targets` (jsonb), `features` (jsonb), `detected_at`, `expires_at`, `status`, `metadata`
- **Deliverable:** Trade setups as first-class records.
- **Acceptance Criteria:**
  - Setup state transitions are testable in isolation
  - Services can store/read setups without affecting other features

---



## Day 22 — Trading Lifecycle Tables

### Task 22.1: Create Orders Table (Migration 9)
- **Columns:** `order_id` (unique), `broker_order_id` (indexed), `trade_setup_id` (FK, optional), `instrument_id` (FK), `status`, `side`, `quantity`, `price`, `order_type`, `product_type`, `filled_quantity`, `avg_fill_price`, `submitted_at`, `filled_at`, `cancelled_at`, `rejection_reason`, `metadata`
- **Deliverable:** DhanHQ-compatible order record.

### Task 22.2: Create Positions Table (Migration 10)
- **Columns:** `position_id` (unique), `order_id` (FK, optional), `instrument_id` (FK), `entry_price`, `quantity`, `side`, `unrealized_pnl`, `realized_pnl`, `stop_loss`, `targets` (jsonb), `status`, `opened_at`, `closed_at`, `metadata`
- **Deliverable:** Position lifecycle with Greeks and regime metadata.

### Task 22.3: Create Trades Table (Migration 11)
- **Columns:** `position_id`, `instrument_id` (FK), `entry_time`, `exit_time`, `entry_price`, `exit_price`, `quantity`, `side`, `gross_pnl`, `net_pnl`, `mfe`, `mae`, `holding_time_seconds`, `outcome`, `exit_reason`, `fees`, `slippage`, `metadata`
- **Deliverable:** Audit-grade closed trades.

---



## Day 23 — Feature & AI Metadata Tables

### Task 23.1: Create Trade Features Table (Migration 12)
- **Columns:** `trade_id` (FK), `entry_features` (jsonb), `exit_features` (jsonb), `regime_at_entry`, `regime_at_exit`, `greeks_at_entry` (jsonb), `greeks_at_exit` (jsonb), `market_structure_at_entry` (jsonb), `metadata`
- **Deliverable:** Reproducible trade context for AI analysis.

### Task 23.2: Create AI Analyses Table (Migration 13)
- **Columns:** `analysis_type`, `related_type`, `related_id`, `model_used`, `prompt`, `response`, `latency_ms`, `tokens_used`, `cost_usd`, `confidence`, `created_at`, `metadata`
- **Deliverable:** LLM analysis log.
- **Commit:** `feat: create trade features + ai analyses tables`

### Task 23.3: Create Learning Records Table (Migration 14)
- **Columns:** `strategy_name`, `time_window`, `window_start`, `window_end`, `expectancy`, `win_rate`, `avg_rr`, `profit_factor`, `sharpe_ratio`, `max_drawdown`, `sample_size`, `total_pnl`, `metadata`
- **Unique Index:** `[:strategy_name, :time_window, :window_start, :window_end]`
- **Deliverable:** Strategy performance ledger.

---



## Day 24 — Indexes, Consistency & Schema Hardening

### Task 24.1: Add Composite Indexes Across Time-Series Tables
- **Goal:** Review all hypertable and feature tables for missing index coverage.
- **Deliverable:** Additional migrations for composite indexes on frequently queried columns.
- **Acceptance Criteria:**
  - `bin/rails db:migrate` completes without duplicates
  - Common queries (`latest`, `range`, `snapshot_at`) use appropriate indexes

### Task 24.2: Add pg_trgm Extension + GIN Indexes
- **Goal:** Enable fuzzy matching and jsonb query support.
- **Deliverable:** `enable_extension 'pg_trgm'` migration; GIN indexes on jsonb metadata columns used for filtering.
- **Acceptance Criteria:**
  - `SELECT 'a' %> 'b'` works after migration
  - JSONB queries run fast on sample bulk loads

### Task 24.3: Add Database Consistency Checks
- **Gem:** `database_consistency`
- **Goal:** Verify foreign keys, null constraints, and enum consistency.
- **Deliverable:** `bin/rails db:consistent` (or equivalent) runs clean after schema.
- **Commit:** `feat: hardening indexes + consistency checks`

---



## Day 25 — Seed Data & End-to-End Validation

### Task 25.1: Create Seed Script for Instrument Master
- **File:** `db/seeds/instruments.rb`
- **Goal:** Populate NIFTY, BANKNIFTY, SENSEX, FINNIFTY with active expiries and ATM±20 strikes.
- **Deliverable:** Self-contained seed file.
- **Acceptance Criteria:**
  - `bin/rails db:seed` inserts the expected instrument count
  - Seed can be re-run idempotently
  - Data is validated against real DhanHQ security IDs

### Task 25.2: Add Rollback Tests for Migrations
- **Goal:** Prevent destructive migrations; verify reversible schema changes.
- **Deliverable:** Rake task or helper script for migration up/down verification.
- **Acceptance Criteria:**
  - `rails db:migrate:down VERSION=...` succeeds for all recent migrations
  - No data loss warnings on tables with optional rollback behavior
  - Tests capture expected exceptions for irreversible changes

### Task 25.3: Document Schema Choices
- **File:** `docs/database_schema.md`
- **Goal:** Explain table purposes, column decisions, and TimescaleDB usage.
- **Deliverable:** Markdown schema documentation.
- **Commit:** `docs: add database schema documentation`

---



## Day 26 — Milano / Iceberg Cross-Model Verification (QUANTA / BITTEN)

### Task 26.1: QUANTA Milano Schematic Inspection
- **Context:** Verify QUANTA Milano instrumentation and schema expectations.
- **Deliverable:** Notes comparing QUANTA Milano requirements with current implementation.
- **Acceptance Criteria:**
  - Mappings from QUANTA Milano to our models are explicit
  - Any missing fields or mismatched nomenclature are highlighted

### Task 26.2: BITTEN Iceberg Cross-Check
- **Context:** Review BITTEN Iceberg architecture against our tables and contracts.
- **Deliverable:** Cross-check summary identifying gaps or overlaps.
- **Acceptance Criteria:**
  - Cross-check references both market data and order models
  - Findings are traceable back to schema changes in prior days

### Task 26.3: Update CONVNOTE / Alias Mappings
- **Context:** Formalize Quinn's MCP analysis mappings for test alignment.
- **Deliverable:** Updated CONVNOTE-formatted alias mapping for test schemas.
- **Acceptance Criteria:**
  - CONVNOTE is still technically usable
  - Test code can reference aliases consistently

---



## Day 27 — Final Integration Tests & Review

### Task 27.1: Build Comprehensive Schema Tests
- **Goal:** Ensure no schema regression.
- **Deliverable:** RSpec tests that verify indexes, constraints, and referential integrity.
- **Acceptance Criteria:**
  - `bundle exec rspec spec/schema/` passes
  - Missing index tests fail on intentionally wrong schema state
  - Tests run in CI with PostgreSQL service

### Task 27.2: Validate TimescaleDB Features End-to-End
- **Goal:** Prove hypertable advantages work.
- **Deliverable:** Performance test logs showing compression and continuous aggregates.
- **Acceptance Criteria:**
  - Compression verification query returns expected stored bytes
  - Continuous aggregate refreshes succeed

### Task 27.3: Archive Milestone Baseline
- **Action:** Tag code and update README with milestone completion date and rollback procedure.
- **Deliverable:** Git tag + README update.
- **Acceptance Criteria:**
  - `git tag` shows `m0.3-complete`
  - README points to this milestone and next step
- **Commit:** `chore: milestone 0.3 complete`

---



## Day 28 — Lesson Log, Measurement & Row Security

### Task 28.1: Log Daily 0.4 / Lesson Log Events
- **Goal:** Capture what worked and what needs revision before Milestone 0.4.
- **Deliverable:** Lesson log summary in `docs/milestone-0.3-lessons.md`.
- **Acceptance Criteria:**
  - Top 5 wins and top 5 risks are recorded
  - Lessons link to specific tasks in this document

### Task 28.2: Measurement Test Validation
- **Goal:** Ensure numeric fields align with expected precision and scoping.
- **Deliverable:** Test matrix showing decimal precision on representative rows.
- **Acceptance Criteria:**
  - All relevant numeric columns tested with boundary values
  - No silent rounding or overflow

### Task 28.3: RLS Exploration & Rejection Analysis
- **Context:** Explore requiring/not requiring Row-Level Security in this Milestone.
- **Deliverable:** A clear recommendation document stating RLS posture.
- **Acceptance Criteria:**
  - Document explains why RLS is needed (or explicitly deferred)
  - Decision is reviewable by security-aware stakeholders

### Task 28.4: Cleanup & Polish
- **Goal:** Finalize all artifacts and verify no orphan files remain.
- **Deliverable:** Repo cleaned; README updated; all Milestone 0.3 changes committed.
- **Acceptance Criteria:**
  - `git status` shows no unexpected unstaged files
  - Milestone 0.3 sign-off checklist is complete
- **Commit:** `chore: milestone 0.3 polish + readiness`

---



## Sprint Checklist & Definition of Done

| # | Deliverable | Verification Method |
|---|------------|---------------------|
| 1 | All 14 migrations run cleanly | `bin/rails db:migrate` exit code 0 |
| 2 | TimescaleDB hypertables created | `\d+ market_ticks` confirms TimescaleDB |
| 3 | Compression policies active | `add_compression_policy` test passes |
| 4 | Seed data loads cleanly | `db:seed` count assertions |
| 5 | Rollback tests pass | Migration down/up verification |
| 6 | RSpec schema tests green | `bundle exec rspec spec/schema/` |
| 7 | database_consistency passes | CI job exit 0 |
| 8 | CONVNOTE aliases mapped | Alias tests pass |
| 9 | Milestone tagged | `git tag` exists |
| 10 | README updated | Readable by onboarding engineer |

---

## Next Steps

After Milestone 0.3 is complete, the next sprint is **Milestone 0.4: Core Service Architecture** (service layer, BaseService, Result object, repositories, engines, event bus, DI container).
