# Milestone 7.2: AI Agents

**Phase:** 7 — AI Gateway  
**Goal:** Specialized AI agents for interpretation, not execution.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement SetupValidatorAgent
- [ ] Create `app/agents/setup_validator_agent.rb`
- [ ] Purpose: Score deterministic trade setups before entry
- [ ] Input: `TradeSetup` + all engine outputs + strike selection
- [ ] Prompt template: `app/prompts/setup_validation.md`
- [ ] Output schema:
  ```json
  {
    "validation_score": 0-100,
    "agree_with_entry": true/false,
    "concerns": ["string"],
    "additional_factors": ["string"],
    "risk_assessment": "low/medium/high",
    "position_size_suggestion": "full/half/quarter/skip"
  }
  ```
- [ ] Threshold: only proceed if `validation_score >= 70` AND `agree_with_entry == true`
- [ ] Latency budget: 15s

### 2. Create MarketAnalystAgent
- [ ] Create `app/agents/market_analyst_agent.rb`
- [ ] Purpose: Generate 5-minute narrative for dashboard/alerts
- [ ] Input: Current regime, structure, momentum, option flow, key levels
- [ ] Prompt template: `app/prompts/market_analysis.md`
- [ ] Output schema:
  ```json
  {
    "narrative": "string (2-3 paragraphs)",
    "key_levels": {"support": [], "resistance": []},
    "directional_bias": "bullish/bearish/neutral",
    "confidence": 0-100,
    "time_horizon": "intraday/swing",
    "risk_factors": ["string"]
  }
  ```
- [ ] Runs every 5 minutes during market hours
- [ ] Latency budget: 20s

### 3. Implement TradeReviewerAgent
- [ ] Create `app/agents/trade_reviewer_agent.rb`
- [ ] Purpose: Post-trade analysis for learning
- [ ] Input: Complete trade record (entry, exit, all engine states, P&L, MFE/MAE)
- [ ] Prompt template: `app/prompts/trade_review.md`
- [ ] Output schema:
  ```json
  {
    "entry_quality": 0-100,
    "exit_quality": 0-100,
    "what_went_well": ["string"],
    "what_could_improve": ["string"],
    "lessons_learned": ["string"],
    "pattern_tags": ["string"],
    "regime_match": true/false
  }
  ```
- [ ] Runs after every closed trade
- [ ] Latency budget: 30s

### 4. Create JournalWriterAgent
- [ ] Create `app/agents/journal_writer_agent.rb`
- [ ] Purpose: Structured trade journaling for human review
- [ ] Input: Trade data + TradeReviewerAgent output
- [ ] Prompt template: `app/prompts/journal.md`
- [ ] Output: Markdown formatted journal entry
- [ ] Sections: Setup, Execution, Management, Outcome, Psychology, Lessons
- [ ] Save to `trade_journals` table and file system
- [ ] Latency budget: 15s

### 5. Implement StrategyResearcherAgent
- [ ] Create `app/agents/strategy_researcher_agent.rb`
- [ ] Purpose: Historical pattern analysis for strategy improvement
- [ ] Input: Query + similar historical trades (from vector store)
- [ ] Prompt template: `app/prompts/research.md`
- [ ] Output schema:
  ```json
  {
    "findings": "string",
    "similar_trades_analyzed": N,
    "win_rate_in_context": 0-100,
    "avg_rr_in_context": 0.0,
    "recommendations": ["string"],
    "parameter_suggestions": {"param": "value"}
  }
  ```
- [ ] Triggered: weekly, or on-demand via dashboard
- [ ] Latency budget: 60s

### 6. Add PromptTemplate System
- [ ] Create `app/agents/prompt_template.rb`
- [ ] ERB-based templates in `app/prompts/`
- [ ] Variables: all engine outputs, trade data, context
- [ ] Helpers: `format_json`, `truncate`, `summarize_array`
- [ ] Version control: prompt versions tracked in git
- [ ] Hot reload in development

### 7. Create app/prompts/setup.md
- [ ] System prompt: "You are an expert options trader validating a naked buy setup..."
- [ ] User prompt template with all engine scores, structure, regime, Greeks, strike analysis
- [ ] Few-shot examples: 3 good setups, 3 bad setups with explanations
- [ ] Output format: strict JSON schema

### 8. Create app/prompts/review.md
- [ ] System prompt: "You are a trading coach reviewing a completed trade..."
- [ ] User prompt: full trade timeline with all engine states at entry/exit
- [ ] Focus: decision quality, not outcome bias
- [ ] Output format: structured JSON

### 9. Create app/prompts/journal.md
- [ ] System prompt: "You are a professional trading journal writer..."
- [ ] User prompt: trade data + review output
- [ ] Output: Markdown with YAML frontmatter
- [ ] Include: charts references (links to dashboard)

### 10. Implement ResponseParser
- [ ] Create `app/agents/response_parser.rb`
- [ ] Parse JSON from LLM response (handle markdown code fences)
- [ ] Validate against JSON schema (using `json_schemer`)
- [ ] Retry on parse failure (max 2, with corrected prompt)
- [ ] Fallback: structured text extraction if JSON fails

### 11. Add AIConfidenceScorer
- [ ] Create `app/agents/ai_confidence_scorer.rb`
- [ ] Score model response reliability:
  - Token probability analysis (if available)
  - Response length vs expected
  - Consistency with deterministic engine outputs
  - Self-consistency (ask same question twice)
- [ ] Output: `confidence` 0-100, `flags` array
- [ ] Low confidence (< 60) → flag for human review

### 12. Create AIAnalysisCache
- [ ] Create `app/agents/ai_analysis_cache.rb`
- [ ] Key: hash of prompt + model + temperature
- [ ] TTL: 10 minutes (market data changes fast)
- [ ] Invalidate on: new candle, regime change, structure break
- [ ] Storage: Redis with compression
- [ ] Metrics: hit rate, cache size, eviction rate

### 13. Implement AgentOrchestrator
- [ ] Create `app/agents/agent_orchestrator.rb`
- [ ] Route requests to correct agent:
  - `validate_setup` → SetupValidatorAgent
  - `analyze_market` → MarketAnalystAgent
  - `review_trade` → TradeReviewerAgent
  - `write_journal` → JournalWriterAgent
  - `research` → StrategyResearcherAgent
- [ ] Sequential vs parallel execution
- [ ] Timeout management per agent
- [ ] Error handling: agent failure doesn't block trading

### 14. Write Tests for Each Agent
- [ ] Create `spec/agents/` with mock LLM responses
- [ ] Test each agent with:
  - Valid input → correct output schema
  - Edge cases (extreme values, missing data)
  - Parse failures → retry logic
  - Low confidence → flagging
  - Cache hits/misses
- [ ] Integration: full agent pipeline with recorded prompts

---

## Acceptance Criteria
- [ ] All 5 agents implemented and tested
- [ ] Prompt templates in `app/prompts/` with version control
- [ ] Response parsing handles malformed JSON
- [ ] Cache reduces redundant API calls by > 50%
- [ ] Confidence scorer flags low-quality responses
- [ ] Orchestrator routes correctly and handles timeouts
- [ ] Latency budgets met for each agent type
- [ ] AI analysis stored in `ai_analyses` table

---

## Notes
- Agents NEVER make trading decisions (entry/exit/size)
- Agents only: validate, analyze, review, journal, research
- Deterministic engines are the source of truth
- AI is a "second opinion" and documentation layer
- Prompt engineering is iterative; track versions
- Local models (Ollama) for simple agents, cloud for complex
- Cost monitoring: alert if daily AI cost > $50