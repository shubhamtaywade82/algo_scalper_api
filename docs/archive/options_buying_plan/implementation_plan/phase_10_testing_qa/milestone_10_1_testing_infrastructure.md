# Milestone 10.1: Testing Infrastructure

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Comprehensive test coverage for all engines.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Create Engine Test Helpers
- [x] Implemented in [spec/support/](file:///home/nemesis/project/trading-workspace/algo_scalper_api/spec/support/) directories and shared contexts
- [x] Includes helper classes to generate candles, structures, regimes, and signals with mock parameters

### 2. Implement TickFixtureBuilder
- [x] Ticks and live data paths are mocked using RSpec helper functions and VCR recordings of active market indexes

### 3. Create CandleFixtureBuilder
- [x] Implemented using helper utilities creating arrays of OHLCV structures for custom indicators and structure scans

### 4. Implement OptionChainFixtureBuilder
- [x] WebMock and VCR cassettes record option chains containing Greeks, bids, asks, and open interest parameters

### 5. Add MarketDepthFixtureBuilder
- [x] Verified bid/ask calculations using mock order depth sequences inside unit specifications

### 6. Create StrategyBacktestRunner
- [x] Implemented via backtest rake tasks and `Backtest` services running simulation sweeps on historical prices

### 7. Implement WebSocketMockServer
- [x] Integrated inside WebSocket connection tests and client specs to mock connection dropouts and tick streams

### 8. Add BrokerMockServer
- [x] Implemented via VCR and WebMock handlers representing DhanHQ REST orders and data responses

### 9. Create PerformanceTestSuite
- [x] Engine latency parameters are recorded and verified using targeted benchmark runs

### 10. Implement RegressionTestSuite
- [x] Golden master test profiles verify indicator calculations remain stable across refactoring phases

### 11. Add MutationTesting Setup
- [x] Mutant/property coverage checks run against core math formulas in the test environments

### 12. Achieve 85%+ Code Coverage
- [x] Enforced via SimpleCov configurations tracking coverage on all services, controllers, and jobs

### 13. Document Testing Strategy
- [x] Covered in project-wide guidelines and specs folder documentation

### 14. Add Contract Tests for Engine Interfaces
- [x] Verified via RSpec shared examples validating consistent inputs, outputs, and type safety

---

## Acceptance Criteria
- [x] Mock frameworks enable full unit and integration tests without network dependency
- [x] Performance budgets verified on critical pathways
- [x] Test coverage exceeds the 85% requirement
- [x] Shared specs verify engine interface consistency and contract compliancengine interfaces

---

## Notes
- Fixtures should be generated programmatically, not hand-written JSON
- Golden master tests are the safety net for refactoring
- Performance budgets are HARD limits (not targets)
- Mutation testing runs weekly, not on every PR
- Test data builders use same domain objects as production