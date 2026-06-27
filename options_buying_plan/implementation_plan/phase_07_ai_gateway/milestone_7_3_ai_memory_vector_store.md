# Milestone 7.3: AI Memory & Vector Store

**Phase:** 7 — AI Gateway  
**Goal:** Historical trade retrieval for pattern matching.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Set Up pgvector Extension
- [ ] Enable `pgvector` extension: `CREATE EXTENSION IF NOT EXISTS vector;`
- [ ] Verify version compatibility with PostgreSQL 16+
- [ ] Configure `shared_preload_libraries` for vector if needed
- [ ] Create migration: `rails g migration EnablePgvector`

### 2. Create VectorEmbeddings Table
- [ ] Generate migration: `rails g migration CreateVectorEmbeddings`
- [ ] Columns:
  - `id` (bigserial, PK)
  - `embeddable_type` (string) - Trade, TradeSetup, MarketRegime
  - `embeddable_id` (bigint)
  - `embedding` (vector, dimension 768 for nomic-embed-text)
  - `model` (string) - embedding model used
  - `content_hash` (string) - SHA256 of source content
  - `metadata` (jsonb) - regime, strategy, outcome, etc.
  - `created_at` (timestamptz)
- [ ] Index: `CREATE INDEX ON vector_embeddings USING hnsw (embedding vector_cosine_ops);`
- [ ] Composite index: `(embeddable_type, embeddable_id)`

### 3. Implement EmbeddingService
- [ ] Create `app/services/embedding_service.rb`
- [ ] Use local Ollama embeddings: `nomic-embed-text` (768 dims)
- [ ] Endpoint: `POST /api/embeddings` to localhost:11434
- [ ] Batch embedding: up to 100 texts per request
- [ ] Retry logic with exponential backoff
- [ ] Cache embeddings in Redis (key: content_hash)
- [ ] Methods: `embed(text)`, `embed_batch(texts)`

### 4. Add TradeEmbedder
- [ ] Create `app/services/trade_embedder.rb`
- [ ] Convert trade to embedding text:
  ```
  Strategy: ORB
  Regime: trending_up
  Structure: HH, HL, BOS
  Entry: NIFTY 25000 CE, delta 0.52, IV rank 35
  Exit: target hit at 2R
  P&L: +4500
  MFE: +6200, MAE: -800
  Holding: 45 min
  ```
- [ ] Include: strategy, regime, structure, option metrics, outcome
- [ ] Generate embedding after trade closes (via callback)
- [ ] Store in `vector_embeddings` with `embeddable_type: 'Trade'`

### 5. Create VectorStore
- [ ] Create `app/services/vector_store.rb`
- [ ] Methods:
  - `upsert(embeddable, embedding, metadata)`
  - `search(query_embedding, limit: 10, filters: {})`
  - `delete(embeddable_type, embeddable_id)`
- [ ] Similarity: cosine distance (1 - cosine similarity)
- [ ] Filter by: strategy, regime, outcome, date range
- [ ] Pagination support for large result sets

### 6. Implement SimilarTradeFinder
- [ ] Create `app/services/similar_trade_finder.rb`
- [ ] Input: current trade setup (pre-entry) or closed trade (post)
- [ ] Query: embed current context, search vector store
- [ ] Filters: same strategy, same regime, same expiry proximity
- [ ] Output: `SimilarTrades` with:
  - `trades` (array of {trade, similarity, outcome})
  - `aggregate_stats` (win rate, avg RR, avg hold time)
  - `pattern_insights` (common factors in winners/losers)

### 7. Add PatternMatcher
- [ ] Create `app/services/pattern_matcher.rb`
- [ ] Find similar market contexts (not just trades)
- [ ] Embed: regime + structure + momentum + option flow snapshot
- [ ] Search for similar market states
- [ ] Output: `MarketPatternMatch` with:
  - `similar_contexts` (regime, structure, outcome)
  - `forward_returns` (distribution of next 30/60/120 min returns)
  - `optimal_actions` (what worked in similar contexts)

### 8. Create AIContextEnricher
- [ ] Create `app/services/ai_context_enricher.rb`
- [ ] Enrich AI prompts with historical context:
  - "Last 5 similar setups: 4 wins, avg RR 2.3"
  - "In trending_up + HH/HL regime: ORB wins 78%"
  - "Current IV rank 35 similar to trades with 85% win rate"
- [ ] Inject into agent prompts via `PromptTemplate` helpers
- [ ] Cache enriched context per setup (TTL: 5 min)

### 9. Implement Embedding Generation Job
- [ ] Create `app/jobs/embedding_generation_job.rb`
- [ ] Trigger: after trade closes (callback from Trade model)
- [ ] Also: daily batch for any missed trades
- [ ] Batch size: 50 trades per job
- [ ] Retry failed embeddings
- [ ] Metrics: embeddings generated, failed, latency

### 10. Write Tests for Similarity Search Accuracy
- [ ] Create `spec/services/vector_store_spec.rb`
- [ ] Test fixtures: known trades with known outcomes
- [ ] Verify:
  - Same strategy + regime returns high similarity
  - Different regime returns low similarity
  - Similar trades have similar outcomes
  - Filter by strategy/regime works
  - Search latency < 100ms for 10k vectors
- [ ] Benchmark: 100k vectors, search performance

---

## Acceptance Criteria
- [ ] pgvector extension enabled and indexed
- [ ] Embedding service generates 768-dim vectors via local Ollama
- [ ] Trade embeddings created automatically on trade close
- [ ] Similar trade finder returns relevant historical trades
- [ ] Pattern matcher identifies regime/structure similarities
- [ ] AI context enricher adds value to agent prompts
- [ ] Search latency < 100ms at 10k vectors
- [ ] HNSW index enables fast approximate nearest neighbor
- [ ] All tests pass with known similarity benchmarks

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