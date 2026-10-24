Here is a **35-milestone, 312-task implementation plan** for building an institutional-grade naked options buying platform on your existing Rails stack (Rails 8.1.3, DhanHQ v2, PostgreSQL, Solid Queue, Redis).

---

# AlgoScalperApi — Complete Implementation Roadmap

**Total Milestones:** 35 | **Total Tasks:** 312 | **Estimated Duration:** 24–32 weeks (1–2 devs)

---

## Phase 0 — Foundation & Tooling

### Milestone 0.1: Repository & DevOps Foundation
**Goal:** Production-ready Rails environment with strict quality gates.

**Tasks:**
1. Initialize Rails 8.1.3 app with `api` mode + `postgresql`
2. Configure `rubocop` with `rubocop-rails`, `rubocop-performance`, `rubocop-rspec`
3. Configure `brakeman` for security scanning
4. Configure `bundler-audit` for dependency vulnerability checks
5. Set up `GitHub Actions` CI pipeline: lint → security → test → build
6. Configure `Docker` + `docker-compose` with multi-stage build
7. Add `HEALTHCHECK` endpoint to Dockerfile
8. Configure `pre-commit` hooks for linting and formatting
9. Set up `rspec` with `factory_bot_rails`, `faker`, `shoulda-matchers`
10. Configure `simplecov` with 80% coverage threshold
11. Add `bullet` gem for N+1 detection in development
12. Set up `rack-attack` for rate limiting and throttling
13. Configure `lograge` for production log formatting
14. Add `appsignal` or `sentry-rails` for error monitoring
15. Create `Makefile` with common dev commands (`setup`, `test`, `lint`, `console`)

---

### Milestone 0.2: Configuration & Environment Management
**Goal:** Environment-aware, type-safe configuration using Pydantic-equivalent patterns.

**Tasks:**
1. Install `dry-configurable` and `dry-struct` for typed settings
2. Create `AppConfig` class with validation for all trading parameters
3. Set up `.env`, `.env.development`, `.env.paper`, `.env.production`
4. Configure `Rails.application.credentials` for API keys and secrets
5. Add `config/initializers/dhanhq.rb` for broker configuration
6. Create `config/initializers/redis.rb` for Redis connection pooling
7. Configure `Solid Queue` with dedicated database and monitoring
8. Configure `Solid Cache` with TTL policies for market data
9. Configure `Solid Cable` for real-time dashboard updates
10. Add environment validation that fails fast on missing required keys
11. Create `bin/setup` script for one-command developer onboarding
12. Document all configuration variables in `docs/configuration.md`

---

### Milestone 0.3: Domain Model & Database Schema
**Goal:** Core domain entities that all engines will consume and produce.

**Tasks:**
1. Create `instruments` table: `exchange_segment`, `security_id`, `trading_symbol`, `expiry`, `strike`, `option_type`, `instrument_type`, `lot_size`, `tick_size`
2. Create `market_ticks` table with TimescaleDB hypertable setup
3. Create `candles` table: `timeframe`, `open`, `high`, `low`, `close`, `volume`, `oi`, `vwap`
4. Create `option_chain_snapshots` table: `snapshot_time`, `strike`, `ce_oi`, `pe_oi`, `ce_volume`, `pe_volume`, `iv`, `delta`, `gamma`, `theta`, `vega`, `bid`, `ask`, `spread`
5. Create `market_depth_snapshots` table: `bid_levels`, `ask_levels`, `bid_imbalance`, `ask_imbalance`
6. Create `market_regimes` table: `regime_type`, `regime_score`, `timeframe`, `detected_at`
7. Create `market_structures` table: `structure_type`, `higher_high`, `higher_low`, `lower_high`, `lower_low`, `bos`, `choch`
8. Create `trade_setups` table: `setup_type`, `direction`, `confidence`, `features`, `detected_at`
9. Create `trade_scores` table: `component_scores`, `total_score`, `threshold`, `passed`
10. Create `orders` table: `order_id`, `broker_order_id`, `status`, `side`, `quantity`, `price`, `order_type`, `product_type`
11. Create `positions` table: `position_id`, `instrument_id`, `entry_price`, `quantity`, `side`, `unrealized_pnl`, `realized_pnl`, `status`
12. Create `trades` table (closed positions): `entry_time`, `exit_time`, `entry_price`, `exit_price`, `mfe`, `mae`, `holding_time`, `outcome`
13. Create `trade_features` table: `entry_features`, `exit_features`, `regime_at_entry`, `greeks_at_entry`
14. Create `ai_analyses` table: `analysis_type`, `model_used`, `prompt`, `response`, `latency_ms`
15. Create `learning_records` table: `strategy_name`, `expectancy`, `win_rate`, `avg_rr`, `sample_size`, `time_window`
16. Add composite indexes on all time-series tables (`instrument_id`, `timestamp`)
17. Add `pg_trgm` extension for fuzzy symbol matching
18. Create database migration rollback tests
19. Seed instrument master data for NIFTY, BANKNIFTY, SENSEX, FINNIFTY
20. Add `database_consistency` gem and configure checks

---

### Milestone 0.4: Core Service Architecture
**Goal:** Clean, testable service layer with dependency injection.

**Tasks:**
1. Create `app/services/` directory structure matching engine taxonomy
2. Implement `BaseService` with `call` interface and error handling
3. Implement `Result` object pattern (`success?`, `failure?`, `value`, `error`)
4. Create `ServiceError` hierarchy: `ValidationError`, `BrokerError`, `DataError`, `RiskError`
5. Implement `InstrumentRepository` for instrument lookups
6. Implement `TickRepository` for tick data CRUD
7. Implement `CandleRepository` for OHLC queries
8. Implement `OptionChainRepository` for Greeks and OI queries
9. Create `app/engines/` directory for deterministic trading engines
10. Create `app/gateway/` directory for AI and broker abstractions
11. Implement `EventBus` using Redis pub/sub for inter-engine communication
12. Add `dry-container` for dependency injection wiring
13. Create `app/lib/calculations/` for shared math utilities
14. Implement `Statistics` module: `sma`, `ema`, `std_dev`, `percentile`, `z_score`
15. Add `app/lib/validators/` for input validation helpers
16. Document service boundaries in `docs/architecture.md`

---

## Phase 1 — DhanHQ Integration

### Milestone 1.1: REST Client & Instrument Manager
**Goal:** Reliable, resilient broker REST API wrapper.

**Tasks:**
1. Audit existing DhanHQ gem usage and identify missing v2 endpoints
2. Create `DhanHQ::RestClient` wrapper with automatic retry (exponential backoff)
3. Implement `HistoricalDataService` for OHLCV fetching
4. Implement `OptionChainService` for real-time Greeks and OI
5. Implement `MarketQuoteService` for LTP, OHLC, volume
6. Implement `OrderService` for placement, modification, cancellation
7. Implement `PositionService` for position and holdings queries
8. Implement `FundsService` for margin and available funds
9. Implement `MarginCalculatorService` for pre-trade margin estimation
10. Create `InstrumentManager` that auto-loads NIFTY, BANKNIFTY, SENSEX, FINNIFTY
11. Implement ATM strike calculation with dynamic rolling on expiry
12. Track ATM ±5 strikes with automatic rebalancing on index moves
13. Add request/response logging with sanitized headers
14. Implement circuit breaker pattern for DhanHQ outages
15. Add metrics collection: request latency, error rate, retry count
16. Write VCR-based integration tests for all REST endpoints
17. Add `WebMock` stubs for offline development
18. Create `docs/broker_api.md` mapping all DhanHQ endpoints to services

---

### Milestone 1.2: WebSocket Manager
**Goal:** Fault-tolerant, auto-recovering market data streams.

**Tasks:**
1. Create `DhanHQ::WebSocketClient` with `faye-websocket` or `websocket-client-simple`
2. Implement `MarketFeed` handler for tick-by-tick LTP data
3. Implement `MarketDepth` handler for 5-level order book
4. Implement `OrderUpdates` handler for order status events
5. Add automatic reconnection with exponential backoff (max 60s)
6. Implement heartbeat monitoring with 30s timeout detection
7. Add health check endpoint `/health/websocket` returning connection status
8. Implement automatic resubscribe on reconnection
9. Add connection metrics: uptime, reconnections, messages/sec
10. Create `WebSocketSupervisor` using `concurrent-ruby` for connection pooling
11. Implement graceful shutdown with pending message flush
12. Add message deduplication using sequence numbers
13. Create `TickNormalizer` that converts raw ticks to domain `MarketTick` objects
14. Implement backpressure handling when Redis is slow
15. Add `WebSocket` integration tests using mock server
16. Create `scripts/websocket_monitor.rb` for manual connection testing
17. Document WebSocket event schema in `docs/websocket.md`

---

### Milestone 1.3: Data Ingestion Pipeline
**Goal:** Raw market data → normalized domain objects → persistent storage.

**Tasks:**
1. Create `TickIngestionJob` (Solid Queue) that batches ticks every 1s
2. Implement `CandleBuilderJob` that aggregates 1m, 5m, 15m, 30m from ticks
3. Create `OptionChainIngestionJob` that snapshots chain every 30s
4. Implement `MarketDepthIngestionJob` that snapshots depth every 5s
5. Add `DataQualityChecker` that validates tick continuity and flags gaps
6. Implement outlier detection for impossible price moves (>5% in 1s)
7. Create `IngestionMetrics` dashboard data endpoint
8. Add `DataRetentionPolicy` that archives old ticks to cold storage
9. Implement `CandleGapFiller` that interpolates missing candles from historical API
10. Create `InstrumentSyncJob` that runs daily to update symbol master
11. Add `ExchangeCalendar` service that knows market holidays and timings
12. Implement pre-market and post-market data handling
13. Write performance tests: target <50ms ingestion latency per tick
14. Add `PgHero` for PostgreSQL query performance monitoring

---

## Phase 2 — Data Platform

### Milestone 2.1: Tick Store & Time-Series Database
**Goal:** High-performance tick storage with TimescaleDB.

**Tasks:**
1. Install and configure TimescaleDB extension
2. Convert `market_ticks` to hypertable partitioned by time
3. Create continuous aggregates for 1m, 5m, 15m, 30m candles
4. Implement compression policy for ticks older than 7 days
5. Add retention policy: raw ticks 30 days, aggregates 1 year
6. Create `TickQueryService` with time-range and instrument filters
7. Implement `TickReplayService` for historical strategy backtesting
8. Add `COPY` based bulk import for historical data seeding
9. Create indexes on `instrument_id + timestamp` for all time-series tables
10. Benchmark tick ingestion: target 10,000 ticks/second
11. Add `pg_stat_statements` tracking for query optimization
12. Document schema in `docs/database.md`

---

### Milestone 2.2: Candle Builder & Historical Database
**Goal:** Reliable OHLC generation from ticks with gap handling.

**Tasks:**
1. Implement `CandleBuilder` with configurable timeframes
2. Add `TickAggregator` that handles incomplete candles
3. Implement `CandleGapDetector` for missing timeframe intervals
4. Create `HistoricalDataSyncJob` that fills gaps from DhanHQ historical API
5. Add `VWAPCalculator` per candle using tick volume
6. Implement `OIChangeCalculator` for open interest deltas
7. Create `RelativeVolumeCalculator` comparing current to average
8. Add `OpeningRangeCalculator` for first 15m/30m ranges
9. Implement `PreviousHighLowTracker` for daily/weekly levels
10. Create `CandleRepository` with efficient time-range queries
11. Add `candles` API endpoint for dashboard charting
12. Write unit tests for all candle math with edge cases

---

### Milestone 2.3: Option Chain Data Store
**Goal:** Rich option chain analytics with derived metrics.

**Tasks:**
1. Create `OptionChainSnapshot` model with all Greeks fields
2. Implement `OIChangeCalculator` for CE/PE OI delta
3. Add `VolumeChangeCalculator` for option volume trends
4. Create `IVRankCalculator` using 52-week IV history
5. Implement `IVPercentileCalculator` for current IV context
6. Add `SpreadCalculator` for bid-ask spread tracking
7. Create `LiquidityScoreCalculator` for each strike
8. Implement `GammaVelocityCalculator` (change in gamma)
9. Add `GammaAccelerationCalculator` (second derivative)
10. Create `ThetaDecayEstimator` for expected decay until exit
11. Implement `OIClassification` (Long Build-up, Short Build-up, etc.)
12. Add `OptionFlowScore` combining OI, volume, and price direction
13. Create `OptionChainRepository` with efficient strike-range queries
14. Write tests for all option analytics calculations

---

## Phase 3 — Feature Engineering

### Milestone 3.1: Underlying Indicators
**Goal:** All technical indicators needed by downstream engines.

**Tasks:**
1. Implement `EMAIndicator` with configurable periods (9, 21, 50, 200)
2. Implement `VWAPIndicator` with standard deviation bands
3. Implement `ATRIndicator` for volatility measurement
4. Implement `ADXIndicator` for trend strength
5. Implement `RSIIndicator` with 14-period default
6. Implement `MACDIndicator` with signal line and histogram
7. Implement `SupertrendIndicator` with configurable ATR multiplier
8. Implement `VolumeProfileIndicator` for price-level volume
9. Implement `RelativeVolumeIndicator` comparing to 20-day average
10. Implement `OpeningRangeIndicator` for first 15m/30m breakout
11. Implement `ROCIndicator` for rate of change
12. Implement `BollingerBandsIndicator` for volatility bands
13. Create `IndicatorCache` using Redis for computed values
14. Add `IndicatorValidator` that checks for sufficient data
15. Implement `IndicatorRegistry` for dynamic indicator loading
16. Write mathematical accuracy tests against known reference values
17. Add performance benchmarks: target <1ms per indicator per candle

---

### Milestone 3.2: Option Features
**Goal:** Greeks-derived and option-specific features.

**Tasks:**
1. Implement `DeltaFeature` with ideal range scoring (0.40–0.65)
2. Implement `GammaFeature` with velocity and acceleration
3. Implement `ThetaFeature` with decay vs expected move comparison
4. Implement `VegaFeature` for IV sensitivity
5. Create `IVRankFeature` using historical IV percentile
6. Implement `IVTrendFeature` for rising/falling classification
7. Add `OIFlowFeature` for directional OI interpretation
8. Implement `VolumeFlowFeature` for option volume analysis
9. Create `SpreadFeature` for liquidity assessment
10. Implement `LiquidityScoreFeature` composite of spread, depth, volume, OI
11. Add `GammaScoreFeature` for strike responsiveness
12. Create `OptionFeatureNormalizer` that scales all features 0–100
13. Implement `FeatureStore` in Redis for real-time feature access
14. Add feature freshness validation (reject stale data >5s)
15. Write tests for feature accuracy and edge cases

---

## Phase 4 — Market Intelligence Engines

### Milestone 4.1: Market Context Engine
**Goal:** Macro filter that decides if trading should be allowed.

**Tasks:**
1. Implement `MarketContextEngine` with `allow_trading` interface
2. Add `GapAnalyzer` for pre-market gap classification
3. Implement `OvernightNewsChecker` (placeholder for news API integration)
4. Create `IndiaVIXAnalyzer` for volatility regime
5. Add `ExpiryChecker` that adjusts rules on expiry day
6. Implement `EventCalendar` for RBI/Fed events
7. Create `HolidaySessionDetector` using exchange calendar
8. Add `PreviousDayTrendAnalyzer` for overnight bias
9. Implement `MarketOpenAnalyzer` for first 30m behavior
10. Create output enum: `:allow_trading`, `:reduced_risk`, `:no_trade`
11. Add `ContextScoreCalculator` (0–100) for risk adjustment
12. Write tests for each context rule
13. Add integration test with real market data

---

### Milestone 4.2: Market Regime Engine
**Goal:** Classify market into trending, ranging, expanding, compressing, reversing.

**Tasks:**
1. Implement `MarketRegimeEngine` with `classify` interface
2. Add `ADXRegimeClassifier` (trending if ADX > 25)
3. Implement `ATRRegimeClassifier` for expansion/compression
4. Create `EMAAlignmentClassifier` for trend direction
5. Add `VWAPRegimeClassifier` for mean reversion vs trend
6. Implement `RangeDetector` using Bollinger Band width
7. Create `ReversalDetector` using divergence patterns
8. Add multi-timeframe regime aggregation (30m, 15m, 5m)
9. Implement `RegimeScoreCalculator` (0–100)
10. Create `RegimeTransitionDetector` for regime change alerts
11. Add regime persistence tracking (avoid whipsaw)
12. Write tests for each regime type with known data patterns

---

### Milestone 4.3: Market Structure Engine
**Goal:** Detect HH, HL, LH, LL, BOS, CHOCH, liquidity sweeps.

**Tasks:**
1. Implement `MarketStructureEngine` with `analyze` interface
2. Add `SwingPointDetector` for local highs/lows
3. Implement `HigherHighDetector` for bullish structure
4. Implement `HigherLowDetector` for bullish structure
5. Implement `LowerHighDetector` for bearish structure
6. Implement `LowerLowDetector` for bearish structure
7. Create `BreakOfStructureDetector` (BOS)
8. Create `ChangeOfCharacterDetector` (CHOCH)
9. Implement `LiquiditySweepDetector` for stop runs
10. Add `FairValueGapDetector` for imbalance zones
11. Implement `OrderBlockDetector` for institutional levels
12. Create multi-timeframe structure aggregation (15m, 5m, 1m)
13. Add `StructureScoreCalculator` (0–100)
14. Write tests with hand-constructed swing patterns

---

### Milestone 4.4: Momentum Engine
**Goal:** Determine if price is accelerating or dying.

**Tasks:**
1. Implement `MomentumEngine` with `analyze` interface
2. Add `ATRExpansionDetector` for volatility acceleration
3. Implement `EMASlopeCalculator` for trend acceleration
4. Create `VWAPDistanceCalculator` for mean-reversion momentum
5. Add `ROCCalculator` for rate of change momentum
6. Implement `VolumeAccelerationDetector` for volume confirmation
7. Create `MomentumScoreCalculator` (0–100)
8. Add `MomentumDivergenceDetector` for early reversal warning
9. Implement momentum persistence tracking
10. Write tests for acceleration and deceleration scenarios

---

### Milestone 4.5: Liquidity Engine
**Goal:** Reject illiquid markets and estimate slippage.

**Tasks:**
1. Implement `LiquidityEngine` with `assess` interface
2. Add `SpreadAnalyzer` with 0.30% rejection threshold
3. Implement `BidAskImbalanceCalculator` for directional pressure
4. Create `OrderBookPressureAnalyzer` for liquidity walls
5. Add `AbsorptionDetector` for large order handling
6. Implement `SlippageEstimator` for expected execution cost
7. Create `LiquidityScoreCalculator` (0–100)
8. Add `ThinBookDetector` for low depth rejection
9. Implement `LowOIDetector` for option-specific liquidity
10. Create `LowVolumeDetector` for option rejection
11. Write tests with simulated order book scenarios

---

### Milestone 4.6: Option Intelligence Engine
**Goal:** Transform raw option chain into actionable intelligence.

**Tasks:**
1. Implement `OptionIntelligenceEngine` with `analyze` interface
2. Add `OIFlowClassifier` (Long Build-up, Short Build-up, etc.)
3. Implement `GammaVelocityCalculator` for delta responsiveness
4. Create `GammaAccelerationCalculator` for convexity changes
5. Add `IVRankCalculator` with 52-week lookback
6. Implement `IVPercentileCalculator` for relative IV context
7. Create `IVTrendAnalyzer` for rising/falling/elevated IV
8. Add `ThetaDecayAnalyzer` with expected move comparison
9. Implement `GammaScoreCalculator` for strike selection
10. Create `IVScoreCalculator` for entry timing
11. Add `FlowScoreCalculator` for directional conviction
12. Implement `ThetaScoreCalculator` for time risk
13. Create composite `OptionIntelligenceScore` (0–100)
14. Write tests for all OI flow classifications

---

## Phase 5 — Strategy & Decision Layer

### Milestone 5.1: Strategy Interface & Base Classes
**Goal:** Plugin architecture where strategies are interchangeable.

**Tasks:**
1. Create `BaseStrategy` class with required interface
2. Implement `should_enter?` abstract method
3. Implement `should_exit?` abstract method
4. Implement `confidence` abstract method
5. Implement `required_features` abstract method
6. Create `StrategyRegistry` for dynamic strategy loading
7. Add `StrategyValidator` that checks all required features exist
8. Implement `StrategyContext` object passed to all strategies
9. Create `StrategyResult` with `signal`, `direction`, `confidence`, `metadata`
10. Add `StrategyLoader` that discovers strategies from `app/strategies/`
11. Implement strategy versioning for backtesting consistency
12. Write tests for strategy interface compliance

---

### Milestone 5.2: Strategy Implementations
**Goal:** Multiple deterministic strategies as plugins.

**Tasks:**
1. Implement `ORBStrategy` (Opening Range Breakout)
2. Implement `TrendFollowingStrategy` using EMA alignment
3. Implement `PullbackStrategy` using VWAP + structure
4. Implement `LiquiditySweepStrategy` using stop-run detection
5. Implement `BreakoutStrategy` using volume + structure
6. Implement `ReversalStrategy` using divergence + structure
7. Add `MomentumContinuationStrategy` using ATR expansion
8. Implement `RangeExpansionStrategy` for volatility breakout
9. Create strategy parameter configuration per environment
10. Add strategy performance tracking in `learning_records`
11. Write isolated tests for each strategy with fixture data
12. Create `docs/strategies.md` with entry/exit rules

---

### Milestone 5.3: Strike Selection Engine
**Goal:** Score every strike and pick the optimal one.

**Tasks:**
1. Implement `StrikeSelectionEngine` with `select` interface
2. Create `StrikeScorer` that evaluates ATM-3 to ATM+3
3. Add `DeltaScorer` with ideal range weighting
4. Add `LiquidityScorer` using spread and depth
5. Add `GammaScorer` for responsiveness
6. Add `OIScorer` for institutional interest
7. Add `IVScorer` for favorable IV conditions
8. Add `VolumeScorer` for activity confirmation
9. Add `ThetaScorer` for time decay risk
10. Implement `SpreadScorer` for execution cost
11. Create composite `StrikeQualityScore` (0–100)
12. Add `StrikeSelector` that returns highest-scoring strike
13. Implement fallback logic when ideal strike is illiquid
14. Write tests with real option chain snapshots

---

### Milestone 5.4: Trade Scoring Engine
**Goal:** Weighted composite score from all engines.

**Tasks:**
1. Implement `TradeScoringEngine` with `score` interface
2. Create `ScoreWeights` configuration:
   - Market Context: 10%
   - Market Regime: 20%
   - Market Structure: 20%
   - Momentum: 10%
   - Liquidity: 10%
   - Option Flow: 15%
   - Greeks: 10%
   - Strike Quality: 5%
3. Add `ScoreAggregator` that combines all engine outputs
4. Implement `ScoreThreshold` with default 80/100
5. Create `ScoreBreakdown` object for debugging
6. Add `ScoreValidator` that rejects trades below threshold
7. Implement `ScoreHistory` tracking for learning engine
8. Add `ScoreExplanation` generator for AI layer
9. Create `ScoreConfidence` modifier based on data quality
10. Write tests verifying exact math with mock engine outputs

---

## Phase 6 — Risk & Execution

### Milestone 6.1: Risk Validation Engine
**Goal:** Nothing reaches execution without passing risk rules.

**Tasks:**
1. Implement `RiskValidationEngine` with `validate` interface
2. Add `DailyLossLimitChecker` with configurable rupee limit
3. Add `WeeklyLossLimitChecker` with rolling 5-day window
4. Add `MonthlyLossLimitChecker` with calendar month reset
5. Implement `MaxOpenPositionsChecker` per index and total
6. Add `MarginAvailabilityChecker` using DhanHQ margin API
7. Implement `RiskPerTradeCalculator` with percentage of capital
8. Add `PositionSizingCalculator` using Kelly criterion variant
9. Implement `MaxExposureChecker` per index (NIFTY, BANKNIFTY, etc.)
10. Add `TimeFilterChecker` (no trades before 9:20, after 3:15)
11. Implement `ExpiryRuleChecker` (no overnight on expiry)
12. Add `RewardRiskRatioChecker` with minimum 2:1 requirement
13. Create `CorrelationChecker` for position overlap
14. Implement `RiskEvent` logging for audit trail
15. Add `EmergencyStop` that halts all trading on catastrophic loss
16. Write tests for each risk rule with pass/fail scenarios

---

### Milestone 6.2: Execution Engine
**Goal:** Reliable order placement with full state tracking.

**Tasks:**
1. Implement `ExecutionEngine` with `execute` interface
2. Add `LimitOrderPlacer` as default execution method
3. Implement `SLOrderPlacer` for stop-loss entries
4. Add `SuperOrderPlacer` if DhanHQ supports bracket orders
5. Create `OrderSlicer` for large quantity splitting
6. Implement `RetryLogic` with max 3 attempts and backoff
7. Add `PartialFillHandler` for incomplete executions
8. Implement `SlippageMonitor` comparing expected vs actual price
9. Create `OrderStateTracker` using WebSocket order updates
10. Add `ExecutionValidator` that confirms order acceptance
11. Implement `ExecutionMetrics`: avg slippage, fill rate, latency
12. Create `ExecutionJournal` for complete audit trail
13. Add `OrderCancellationService` for emergency exits
14. Write integration tests with mocked broker responses

---

### Milestone 6.3: Position Management Engine
**Goal:** Live monitoring and adaptive trade management.

**Tasks:**
1. Implement `PositionManagementEngine` with `monitor` interface
2. Add `PnLTracker` for real-time unrealized P&L
3. Implement `StructureMonitor` that watches for BOS/CHOCH
4. Create `IVMonitor` for implied volatility changes
5. Add `OIMonitor` for open interest shifts
6. Implement `GammaMonitor` for delta acceleration changes
7. Add `VolumeMonitor` for momentum confirmation/divergence
8. Implement `StopLossManager` with initial SL placement
9. Create `TrailingStopManager` with ATR-based trailing
10. Add `PartialExitManager` for scaling out at targets
11. Implement `TimeDecayMonitor` for theta-based exits
12. Create `EmergencyExitManager` for catastrophic moves
13. Add `PositionReconciliationJob` that syncs with broker every 30s
14. Implement `PositionAlertService` for Telegram notifications
15. Write tests for each management action

---

## Phase 7 — AI Gateway

### Milestone 7.1: AI Gateway Infrastructure
**Goal:** Resilient, multi-provider AI routing layer.

**Tasks:**
1. Create `AIGateway` service with `request` interface
2. Implement `ProviderPool` with priority tiers: primary, secondary, emergency, local
3. Add `OllamaCloudProvider` for cloud API keys
4. Add `OllamaLocalProvider` for localhost:11434
5. Create `KeyManager` that tracks usage per key
6. Implement `RateLimitTracker` per key (requests/minute, requests/day)
7. Add `LatencyTracker` with rolling average per key
8. Implement `FailureTracker` with consecutive failure counting
9. Create `CooldownManager` that pauses failed keys for 5m
10. Add `HealthMonitor` that polls provider status
11. Implement `Router` that selects best available provider
12. Create `AutomaticFailover` on 429/5xx responses
13. Add `RequestTimeout` with graceful degradation
14. Implement `AIGatewayMetrics`: latency, cost, success rate
15. Write tests for failover scenarios

---

### Milestone 7.2: AI Agents
**Goal:** Specialized AI agents for interpretation, not execution.

**Tasks:**
1. Implement `SetupValidatorAgent` that scores deterministic setups
2. Create `MarketAnalystAgent` for 5-minute narrative generation
3. Implement `TradeReviewerAgent` for post-trade analysis
4. Create `JournalWriterAgent` for structured trade journaling
5. Implement `StrategyResearcherAgent` for historical pattern analysis
6. Add `PromptTemplate` system with ERB-based prompt files
7. Create `app/prompts/setup.md` template
8. Create `app/prompts/review.md` template
9. Create `app/prompts/journal.md` template
10. Implement `ResponseParser` for structured AI outputs
11. Add `AIConfidenceScorer` for model response reliability
12. Create `AIAnalysisCache` to avoid redundant calls
13. Implement `AgentOrchestrator` that routes to correct agent
14. Write tests for each agent with mock LLM responses

---

### Milestone 7.3: AI Memory & Vector Store
**Goal:** Historical trade retrieval for pattern matching.

**Tasks:**
1. Set up `pgvector` extension for embeddings
2. Create `vector_embeddings` table
3. Implement `EmbeddingService` using local Ollama embeddings
4. Add `TradeEmbedder` that converts trade features to vectors
5. Create `VectorStore` with similarity search
6. Implement `SimilarTradeFinder` for historical comparison
7. Add `PatternMatcher` that finds similar market contexts
8. Create `AIContextEnricher` that adds historical context to prompts
9. Implement embedding generation job after each trade
10. Write tests for similarity search accuracy

---

## Phase 8 — Learning & Optimization

### Milestone 8.1: Learning Engine
**Goal:** Continuous improvement from every trade.

**Tasks:**
1. Implement `LearningEngine` with `record` and `analyze` interfaces
2. Add `TradeRecorder` that captures entry/exit features
3. Implement `MFECalculator` (Maximum Favorable Excursion)
4. Implement `MAECalculator` (Maximum Adverse Excursion)
5. Add `SlippageAnalyzer` for execution quality
6. Create `HoldingTimeAnalyzer` for time-based patterns
7. Implement `OutcomeClassifier` (win/loss/breakeven)
8. Add `RegimePerformanceAnalyzer` (win rate by regime)
9. Create `TimeOfDayAnalyzer` for session performance
10. Implement `DeltaRangeAnalyzer` for optimal delta selection
11. Add `ExpiryDayAnalyzer` for day-wise performance
12. Create `StrategyExpectancyCalculator` for continuous evaluation
13. Implement `LearningReportGenerator` for weekly summaries
14. Write tests with synthetic trade histories

---

### Milestone 8.2: Performance Analytics
**Goal:** Deep metrics on strategy and execution quality.

**Tasks:**
1. Implement `PerformanceEngine` with `report` interface
2. Add `WinRateCalculator` with statistical significance
3. Implement `ProfitFactorCalculator` (gross profit / gross loss)
4. Create `SharpeRatioCalculator` for risk-adjusted returns
5. Add `SortinoRatioCalculator` for downside risk
6. Implement `CalmarRatioCalculator` for drawdown-adjusted returns
7. Create `DrawdownAnalyzer` with max drawdown tracking
8. Add `ConsecutiveLossAnalyzer` for streak management
9. Implement `ExpectancyCalculator` per strategy
10. Create `PerformanceDashboardData` endpoint
11. Add `BenchmarkComparison` vs buy-and-hold index
12. Write tests with known performance scenarios

---

## Phase 9 — Dashboard & Operations

### Milestone 9.1: Real-Time Dashboard
**Goal:** Operational visibility for live trading.

**Tasks:**
1. Create `DashboardController` with JSON API endpoints
2. Implement `MarketRegimeEndpoint` for current regime display
3. Add `OptionChainEndpoint` for live chain data
4. Create `LiquidityEndpoint` for real-time liquidity scores
5. Implement `CurrentTradesEndpoint` for active positions
6. Add `RiskMetricsEndpoint` for exposure and limits
7. Create `AIAnalysisEndpoint` for latest AI insights
8. Implement `PerformanceEndpoint` for P&L and metrics
9. Add `TradeJournalEndpoint` for recent closed trades
10. Create `WebSocketChannel` for live dashboard updates
11. Implement `HealthEndpoint` for system status
12. Add `AlertHistoryEndpoint` for notification log
13. Write API integration tests

---

### Milestone 9.2: Alerting & Notifications
**Goal:** Multi-channel alerting for critical events.

**Tasks:**
1. Implement `AlertService` with `notify` interface
2. Add `TelegramAlertProvider` using `telegram-bot-ruby`
3. Implement `EmailAlertProvider` for critical failures
4. Create `AlertClassifier` for severity levels (info, warning, critical)
5. Add `TradeEntryAlert` with setup summary
6. Implement `TradeExitAlert` with P&L and reason
7. Create `RiskAlert` for limit breaches
8. Add `SystemAlert` for infrastructure failures
9. Implement `AIInsightAlert` for model analysis
10. Create `AlertThrottler` to prevent spam
11. Add `AlertHistory` for audit trail
12. Write tests for all alert types

---

## Phase 10 — Testing & Quality Assurance

### Milestone 10.1: Testing Infrastructure
**Goal:** Comprehensive test coverage for all engines.

**Tasks:**
1. Create `spec/engines/` directory with test helpers
2. Implement `EngineTestHelper` for mock market data
3. Add `TickFixtureBuilder` for synthetic tick generation
4. Create `CandleFixtureBuilder` for known patterns
5. Implement `OptionChainFixtureBuilder` for Greeks data
6. Add `MarketDepthFixtureBuilder` for order book tests
7. Create `StrategyBacktestRunner` for historical replay
8. Implement `WebSocketMockServer` for connection tests
9. Add `BrokerMockServer` for order execution tests
10. Create `PerformanceTestSuite` for latency benchmarks
11. Implement `RegressionTestSuite` for strategy changes
12. Add `MutationTesting` setup with `mutant` gem
13. Achieve 85%+ code coverage target
14. Document testing strategy in `docs/testing.md`

---

### Milestone 10.2: Paper Trading Mode
**Goal:** Full system validation without real capital.

**Tasks:**
1. Implement `PaperTradingBroker` that mimics DhanHQ responses
2. Create `PaperOrderBook` for simulated matching
3. Add `PaperSlippageSimulator` with realistic fills
4. Implement `PaperPnLCalculator` for unrealized tracking
5. Create `PaperPositionManager` for simulated positions
6. Add `PaperTradingSwitch` in configuration
7. Implement `PaperTradeRecorder` identical to live trades
8. Create `PaperTradingDashboard` with simulated metrics
9. Add `PaperTradingValidator` that confirms system behavior
10. Run 2-week paper trading period as gating criteria
11. Document paper trading results in `docs/paper_trading.md`

---

### Milestone 10.3: Historical Replay & Walk-Forward Testing
**Goal:** Validate strategies on historical data before deployment.

**Tasks:**
1. Implement `HistoricalReplayEngine` for tick-by-tick replay
2. Create `ReplaySpeedController` (1x, 10x, 100x)
3. Add `ReplayMetricsCollector` for strategy performance
4. Implement `WalkForwardTestRunner` with rolling windows
5. Create `MonteCarloSimulator` for randomization tests
6. Add `ParameterOptimization` with grid search
7. Implement `OverfittingDetector` using train/test splits
8. Create `ReplayReportGenerator` with equity curves
9. Add `ReplayComparison` for strategy A/B testing
10. Document replay methodology in `docs/replay.md`

---

## Phase 11 — Live Trading & Operations

### Milestone 11.1: Live Trading Deployment
**Goal:** Production deployment with safety mechanisms.

**Tasks:**
1. Implement `LiveTradingGuard` with capital limits
2. Add `TradingHoursEnforcer` for market open/close
3. Create `BrokerConnectionMonitor` with auto-reconnect
4. Implement `DataQualityGate` that blocks on stale data
5. Add `RiskCircuitBreaker` for daily loss limits
6. Create `EmergencyStopButton` API endpoint
7. Implement `GracefulShutdown` for position reconciliation
8. Add `DeploymentChecklist` with automated validation
9. Create `Runbook` for operational procedures
10. Implement `IncidentResponse` alerting for failures
11. Add `PostTradeReconciliation` with broker statements
12. Document live trading procedures in `docs/live_trading.md`

---

### Milestone 11.2: Monitoring & Observability
**Goal:** Full system visibility in production.

**Tasks:**
1. Implement `MetricsCollector` using `prometheus-client`
2. Add `GrafanaDashboard` for system metrics
3. Create `TradingMetrics`: orders/min, fills/min, slippage avg
4. Implement `EngineMetrics`: latency per engine, queue depth
5. Add `DataMetrics`: tick lag, candle freshness, gap count
6. Create `RiskMetrics`: exposure, margin utilization, drawdown
7. Implement `AIMetrics`: request latency, success rate, cost
8. Add `AlertingRules` for anomaly detection
9. Create `LogAggregation` with structured JSON logging
10. Implement `DistributedTracing` for request flows
11. Add `UptimeMonitoring` with external health checks
12. Document monitoring setup in `docs/monitoring.md`

---

### Milestone 11.3: Continuous Improvement Loop
**Goal:** System that improves from every trading session.

**Tasks:**
1. Implement `DailyReviewJob` that runs at market close
2. Add `TradeClustering` for pattern discovery
3. Create `StrategyOptimizer` that adjusts parameters
4. Implement `FeatureImportanceAnalyzer` using trade outcomes
5. Add `RegimeAdaptation` that shifts strategy weights
6. Create `StrikeSelectionOptimizer` from historical results
7. Implement `RiskParameterTuning` based on drawdowns
8. Add `AIPromptOptimization` from analyst feedback
9. Create `WeeklyRetrospectiveGenerator` with automated reports
10. Implement `MonthlyStrategyReview` for strategic pivots
11. Add `BacktestAutomation` for strategy changes
12. Document improvement process in `docs/continuous_improvement.md`

---

## Summary Table

| Phase | Milestones | Tasks | Focus |
|-------|-----------|-------|-------|
| 0 — Foundation | 0.1–0.4 | 47 | Tooling, config, schema, services |
| 1 — Dhan Integration | 1.1–1.3 | 50 | REST, WebSocket, ingestion |
| 2 — Data Platform | 2.1–2.3 | 37 | TimescaleDB, candles, option chain |
| 3 — Feature Engineering | 3.1–3.2 | 32 | Indicators, Greeks features |
| 4 — Market Intelligence | 4.1–4.6 | 64 | 6 engines: context, regime, structure, momentum, liquidity, option |
| 5 — Strategy & Decisions | 5.1–5.4 | 38 | Strategies, strike selection, scoring |
| 6 — Risk & Execution | 6.1–6.3 | 45 | Risk, execution, position management |
| 7 — AI Gateway | 7.1–7.3 | 39 | Gateway, agents, vector memory |
| 8 — Learning | 8.1–8.2 | 26 | Learning engine, performance analytics |
| 9 — Dashboard | 9.1–9.2 | 25 | Real-time dashboard, alerts |
| 10 — Testing | 10.1–10.3 | 34 | Tests, paper trading, replay |
| 11 — Live Trading | 11.1–11.3 | 36 | Deployment, monitoring, improvement |
| **Total** | **35** | **312** | |

---

**Recommended Execution Order:** Follow milestones sequentially within each phase, but Phase 4 engines can be developed in parallel once Phase 3 is complete. Phase 7 (AI) can run parallel to Phase 5–6. Phase 8 depends on Phase 6 having generated trades.

**Critical Path:** 0.1 → 0.2 → 0.3 → 0.4 → 1.1 → 1.2 → 1.3 → 2.1 → 2.2 → 3.1 → 4.1 → 4.2 → 4.3 → 5.1 → 5.4 → 6.1 → 6.2 → 10.2 → 11.1

Would you like me to **expand any specific milestone into a full sprint plan with daily tasks**, or **generate the Ruby engine interfaces** (base classes, method signatures) for the critical path milestones?