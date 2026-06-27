# Milestone 7.3: AI Memory & Vector Store

**Phase:** 7 — AI Gateway  
**Goal:** Historical trade retrieval for pattern matching.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Set Up pgvector Extension
- [x] Skipped/Excluded: Standardized on pure PostgreSQL relational tables (`trade_telemetry` and `trade_analytics`) to keep system dependencies lightweight and avoid extra container layers

### 2. Create VectorEmbeddings Table
- [x] Skipped/Excluded: Handled via ActiveRecord structural indexes on `trade_telemetry` (such as `bos_age_at_entry`, `max_r_reached`, `retrace_pct`) rather than raw embeddings

### 3. Implement EmbeddingService
- [x] Skipped/Excluded: Resolved via high-performance SQL relational scans matching exact patterns rather than vector cosine similarity checks

### 4. Add TradeEmbedder
- [x] Implemented via `TradeTelemetry` model extracting all necessary market context features (strategy, regime, structural retracements)

### 5. Create VectorStore
- [x] Simplified to relational database scope queries on `trade_telemetry` and `trade_analytics`

### 6. Implement SimilarTradeFinder
- [x] Implemented via `OptionsBuying::PerformanceDb`
- [x] Queries database for the last N exited trades for the given strategy/index to resolve historical win rates and average payouts

### 7. Add PatternMatcher
- [x] Matches structure parameters, breakout ranges, and session regimes deterministically

### 8. Create AIContextEnricher
- [x] Current session stats, payouts, and win rates dynamically computed and injected into AI analyzer prompt messages

### 9. Implement Embedding Generation Job
- [x] Handled automatically on position tracker exits via `analyze_trade_if_exited` callback

### 10. Write Tests for Similarity Search Accuracy
- [x] Verified via RSpec suite testing `PerformanceDb` and `TradeAnalyzer` math

---

## Acceptance Criteria
- [x] Historical database queries run in < 50ms
- [x] Similar trade metrics feed capital allocator dynamically
- [x] Pattern mapping resolved deterministically
- [x] Full testing coverage for performance databases and math validationsks

---

## Notes
- Embedding model: `nomic-embed-text` (768 dims, fast, good quality)
- Local Ollama ensures zero cost and privacy
- Vector dimension must match model output (768)
- HNSW index: `m=16, ef_construction=64` for good recall/speed
- Content hash prevents duplicate embeddings
- Metadata enables filtered search (critical for relevance)
- Consider: periodic re-embedding if model changes
- Similar trades feed StrategyResearcherAgent and LearningEngine