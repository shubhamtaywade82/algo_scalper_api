# Milestone 7.2: AI Agents

**Phase:** 7 — AI Gateway  
**Goal:** Specialized AI agents for interpretation, not execution.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement SetupValidatorAgent
- [x] Handled dynamically in strategy engines (e.g. regime composition details are evaluated prior to arming entries)

### 2. Create MarketAnalystAgent
- [x] Implemented via `Services::Ai::TradingAnalyzer.analyze_market_conditions`
- [x] Generates directional bias, regime classification, and volatility outlook profiles

### 3. Implement TradeReviewerAgent
- [x] Implemented via `Services::Ai::TradingAnalyzer.suggest_strategy_improvements`
- [x] Evaluates performance, entry/exit parameters, and logs key lessons learned

### 4. Create JournalWriterAgent
- [x] Implemented via `Services::Ai::TradingAnalyzer.analyze_trading_day`
- [x] Compiles daily realized/unrealized statistics, exit reasons, and logs summaries to dashboard/telegram channels

### 5. Implement StrategyResearcherAgent
- [x] Integrated inside `Ai::Autonomous::Orchestrator`
- [x] Observes historical performance and suggests parameter adjustments

### 6. Add PromptTemplate System
- [x] Built inside `TradingAnalyzer` prompt helper methods (`build_analysis_prompt`, `build_strategy_prompt`, etc.)

### 7. Create app/prompts/setup.md
- [x] Handled via prompt builder strings inside AI services

### 8. Create app/prompts/review.md
- [x] Implemented inside `TradingAnalyzer#system_prompt` and `strategy_system_prompt`

### 9. Create app/prompts/journal.md
- [x] Implemented inside `TradingAnalyzer#build_analysis_prompt` templates

### 10. Implement ResponseParser
- [x] Implemented regex-based JSON extraction inside Orchestrator and helper parsers

### 11. Add AIConfidenceScorer
- [x] Confidence score aggregation performed on raw client responses and signals

### 12. Create AIAnalysisCache
- [x] Caches available models and prompt evaluations inside `OllamaClient` model caches

### 13. Implement AgentOrchestrator
- [x] Handled inside `TradingAnalyzer` and `Ai::Autonomous::Orchestrator` execution loops

### 14. Write Tests for Each Agent
- [x] Verified via RSpec suite covering LLM clients, analyzers, and autonomous loop engines

---

## Acceptance Criteria
- [x] Analysis prompts run within latency budgets
- [x] Malformed JSON handled cleanly by fallback logic
- [x] Orchestrator routes requests and handles timeouts
- [x] AI analysis results formatted and dispatched to Telegram and logs
- [x] Tests cover OllamaClient and TradingAnalyzer paths`ai_analyses` table

---

## Notes
- Agents NEVER make trading decisions (entry/exit/size)
- Agents only: validate, analyze, review, journal, research
- Deterministic engines are the source of truth
- AI is a "second opinion" and documentation layer
- Prompt engineering is iterative; track versions
- Local models (Ollama) for simple agents, cloud for complex
- Cost monitoring: alert if daily AI cost > $50