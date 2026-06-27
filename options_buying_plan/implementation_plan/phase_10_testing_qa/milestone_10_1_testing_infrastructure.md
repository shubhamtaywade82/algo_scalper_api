# Milestone 10.1: Testing Infrastructure

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Comprehensive test coverage for all engines.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Create Engine Test Helpers
- [ ] Create `spec/support/engine_test_helper.rb`
- [ ] Shared context for engine testing:
  - `build_market_context(overrides = {})`
  - `build_regime_output(overrides = {})`
  - `build_structure_output(overrides = {})`
  - `build_momentum_output(overrides = {})`
  - `build_liquidity_output(overrides = {})`
  - `build_option_intelligence_output(overrides = {})`
- [ ] Helper to run full engine pipeline with mock data

### 2. Implement TickFixtureBuilder
- [ ] Create `spec/support/fixtures/tick_fixture_builder.rb`
- [ ] Generate synthetic ticks with:
  - Configurable price path (random walk, trend, mean reversion)
  - Volume patterns (constant, burst, declining)
  - OI changes (building, unwinding)
  - Timestamp sequences (regular, with gaps)
- [ ] Methods: `build_stream(count, pattern: :trend_up)`, `build_gap_scenario()`

### 3. Create CandleFixtureBuilder
- [ ] Create `spec/support/fixtures/candle_fixture_builder.rb`
- [ ] Known patterns:
  - `bullish_trend` (HH, HL sequence)
  - `bearish_trend` (LH, LL sequence)
  - `range_bound` (oscillating)
  - `breakout` (compression → expansion)
  - `reversal` (divergence + CHOCH)
  - `opening_range` (tight range → break)
- [ ] Each pattern: candles + expected engine outputs

### 4. Implement OptionChainFixtureBuilder
- [ ] Create `spec/support/fixtures/option_chain_fixture_builder.rb`
- [ ] Greeks scenarios:
  - `atm_high_gamma` (0DTE, gamma 0.02+)
  - `otm_low_delta` (delta 0.2-0.3)
  - `iv_crush` (IV drop 30% in 1 hour)
  - `gamma_ramp` (gamma accelerating)
  - `skew_steep` (put IV >> call IV)
- [ ] OI flow scenarios: long buildup, short covering, etc.

### 5. Add MarketDepthFixtureBuilder
- [ ] Create `spec/support/fixtures/market_depth_fixture_builder.rb`
- [ ] Order book scenarios:
  - `liquid` (tight spread, deep book)
  - `thin` (wide spread, shallow)
  - `absorption` (large wall, price absorbs)
  - `sweep` (price spikes through level, recovers)
  - `imbalance` (bid/ask volume 3:1)
- [ ] Generate 5-level depth arrays

### 6. Create StrategyBacktestRunner
- [ ] Create `spec/support/strategy_backtest_runner.rb`
- [ ] Input: strategy, historical candles, option chains
- [ ] Process: replay ticks → engines → strategy signals → score → risk → execution
- [ ] Output: trades array with entry/exit, P&L, MFE/MAE
- [ ] Metrics: win rate, expectancy, max DD, Sharpe
- [ ] Compare: strategy vs buy-and-hold

### 7. Implement WebSocketMockServer
- [ ] Create `spec/support/mocks/websocket_mock_server.rb`
- [ ] Using `websocket-eventmachine-server` or similar
- [ ] Simulate: connect, subscribe, tick stream, depth, order updates
- [ ] Scenarios: normal, reconnect, heartbeat timeout, message burst
- [ ] Programmable: inject custom message sequences

### 8. Add BrokerMockServer
- [ ] Create `spec/support/mocks/broker_mock_server.rb`
- [ ] Sinatra/Rack app mimicking DhanHQ REST API
- [ ] Endpoints: historical, option chain, quotes, orders, positions, funds
- [ ] State: maintains order book, positions, margin
- [ ] Scenarios: success, rejection, partial fill, timeout, rate limit
- [ ] Configurable latency and failure injection

### 9. Create PerformanceTestSuite
- [ ] Create `spec/performance/`
- [ ] Benchmarks per engine:
  - Market Context: < 10ms
  - Market Regime: < 20ms
  - Market Structure: < 30ms
  - Momentum: < 15ms
  - Liquidity: < 10ms
  - Option Intelligence: < 50ms
  - Strike Selection: < 20ms
  - Trade Scoring: < 10ms
  - Risk Validation: < 15ms
  - Execution: < 200ms (with mock broker)
- [ ] Run with `benchmark-ips`, assert thresholds
- [ ] CI: fail if any benchmark regresses > 20%

### 10. Implement RegressionTestSuite
- [ ] Create `spec/regression/`
- [ ] Golden master tests: freeze engine outputs for known inputs
- [ ] Store: `spec/fixtures/golden_master/{engine_name}.json`
- [ ] On change: diff output, require explicit approval
- [ ] Prevents: silent behavior changes in deterministic engines

### 11. Add MutationTesting Setup
- [ ] Add `mutant` gem to Gemfile (test group)
- [ ] Config: `mutant.yml` with:
  - Namespaces: `Engines`, `Calculations`, `Strategies`
  - Min coverage: 85%
  - Timeout: 10s per mutation
- [ ] Run: `bundle exec mutant` in CI (optional, slow)
- [ ] Goal: catch missing edge case tests

### 12. Achieve 85%+ Code Coverage
- [ ] Configure SimpleCov with:
  - Groups: Engines, Calculations, Strategies, Services, Gateway, Jobs
  - Minimum: 85% overall, 90% for engines/calculations
  - Exclude: views, mailers, channels, migrations
- [ ] CI: fail if coverage drops
- [ ] Report: HTML + JSON for CI artifacts

### 13. Document Testing Strategy
- [ ] Create `docs/testing.md` with:
  - Test pyramid: unit > integration > e2e
  - Fixture management
  - Golden master workflow
  - Performance benchmarks
  - Mutation testing
  - CI pipeline stages
  - Local development: `make test`, `make test:unit`, `make test:integration`

### 14. Add Contract Tests for Engine Interfaces
- [ ] Create `spec/contracts/engine_interface_spec.rb`
- [ ] Shared examples for all engines:
  - `responds to #analyze(input)`
  - `returns Output struct with required fields`
  - `handles nil/missing input gracefully`
  - `completes within time budget`
  - `deterministic: same input = same output`
- [ ] Each engine includes shared examples

---

## Acceptance Criteria
- [ ] All 6 engine test helpers work with realistic fixtures
- [ ] Backtest runner produces trade logs matching manual analysis
- [ ] WebSocket/broker mocks enable full integration tests
- [ ] Performance benchmarks pass in CI
- [ ] Regression suite catches unintended changes
- [ ] Mutation testing configured (run manually)
- [ ] Coverage > 85% overall, > 90% for engines
- [ ] Contract tests verify all engine interfaces

---

## Notes
- Fixtures should be generated programmatically, not hand-written JSON
- Golden master tests are the safety net for refactoring
- Performance budgets are HARD limits (not targets)
- Mutation testing runs weekly, not on every PR
- Test data builders use same domain objects as production