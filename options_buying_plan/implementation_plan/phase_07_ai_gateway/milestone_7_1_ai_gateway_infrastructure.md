# Milestone 7.1: AI Gateway Infrastructure

**Phase:** 7 — AI Gateway  
**Goal:** Resilient, multi-provider AI routing layer.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Create AIGateway Service
- [ ] Create `app/gateway/ai_gateway.rb`
- [ ] Interface: `request(prompt, options) -> AIResponse`
- [ ] Options: `model`, `temperature`, `max_tokens`, `system_prompt`, `json_mode`
- [ ] Returns: `AIResponse` with `content`, `tokens_used`, `latency_ms`, `cost_usd`, `provider`, `model`
- [ ] Error handling: `AIError` with provider, error_code, retryable

### 2. Implement ProviderPool
- [ ] Create `app/gateway/ai/provider_pool.rb`
- [ ] Priority tiers:
  - Tier 1 (Primary): Ollama Cloud (API keys)
  - Tier 2 (Secondary): Backup cloud provider (OpenAI, Anthropic)
  - Tier 3 (Emergency): Local Ollama (localhost:11434)
  - Tier 4 (Local): Fallback models (llama3:8b, phi3:mini)
- [ ] Config: `AppConfig.ai.provider_tiers`
- [ ] Health check per provider on startup

### 3. Add OllamaCloudProvider
- [ ] Create `app/gateway/ai/providers/ollama_cloud_provider.rb`
- [ ] HTTP client for Ollama Cloud API
- [ ] Multiple API keys (rotate on rate limit)
- [ ] Models: llama3.1:70b, llama3.1:8b, codellama:34b
- [ ] Streaming support for long responses
- [ ] Auth: Bearer token in header

### 4. Add OllamaLocalProvider
- [ ] Create `app/gateway/ai/providers/ollama_local_provider.rb`
- [ ] HTTP client for localhost:11434
- [ ] Models: llama3:8b, phi3:mini, gemma2:9b (pre-pulled)
- [ ] No auth required
- [ ] Health check: `/api/tags` endpoint

### 5. Create KeyManager
- [ ] Create `app/gateway/ai/key_manager.rb`
- [ ] Track per-key usage:
  - Requests/minute, requests/hour, requests/day
  - Tokens consumed
  - Errors (429, 5xx, timeout)
  - Last used timestamp
- [ ] Storage: Redis hash per key
- [ ] TTL: 24 hours rolling window

### 6. Implement RateLimitTracker
- [ ] Create `app/gateway/ai/rate_limit_tracker.rb`
- [ ] Per-key limits (from provider docs):
  - RPM: 60, RPH: 1000, RPD: 10000
  - TPM: 100000
- [ ] Sliding window algorithm
- [ ] Block key when limit reached
- [ ] Auto-unblock when window slides

### 7. Add LatencyTracker
- [ ] Create `app/gateway/ai/latency_tracker.rb`
- [ ] Rolling average (last 100 requests) per key
- [ ] Percentiles: p50, p95, p99
- [ ] Alert if p99 > 30s
- [ ] Used for provider selection (prefer lower latency)

### 8. Implement FailureTracker
- [ ] Create `app/gateway/ai/failure_tracker.rb`
- [ ] Consecutive failures counter per key
- [ ] Failure types: rate_limit, server_error, timeout, validation_error
- [ ] Threshold: 3 consecutive failures = quarantine
- [ ] Reset on success

### 9. Create CooldownManager
- [ ] Create `app/gateway/ai/cooldown_manager.rb`
- [ ] Quarantine failed keys for 5 minutes (configurable)
- [ ] Exponential backoff for repeated failures: 5m, 15m, 1h
- [ ] Max cooldown: 24 hours
- [ ] Manual override via admin API

### 10. Add HealthMonitor
- [ ] Create `app/gateway/ai/health_monitor.rb`
- [ ] Background job: ping each provider every 60s
- [ ] Check: `/api/tags` (local), `/v1/models` (cloud)
- [ ] Mark unhealthy on: timeout, 5xx, empty model list
- [ ] Auto-recover when healthy for 2 consecutive checks
- [ ] Metrics: `ai_provider_health` (gauge 0/1)

### 11. Implement Router
- [ ] Create `app/gateway/ai/router.rb`
- [ ] Selection algorithm:
  1. Filter healthy, non-quarantined keys
  2. Sort by: tier priority, then latency, then available quota
  3. Pick top key
- [ ] Fallback: if Tier 1 exhausted, use Tier 2, etc.
- [ ] Sticky routing: same key for conversation context (optional)

### 12. Create AutomaticFailover
- [ ] Create `app/gateway/ai/failover_handler.rb`
- [ ] On 429: immediate key switch, retry same request
- [ ] On 5xx: retry once on same key, then switch
- [ ] On timeout: retry once on faster key
- [ ] Max retries: 3 across all keys
- [ ] Log all failovers for analysis

### 13. Add RequestTimeout
- [ ] Configurable timeout per request type:
  - Setup validation: 15s
  - Market analysis: 30s
  - Trade review: 20s
  - Journal: 10s
- [ ] Graceful degradation: return cached/fallback response
- [ ] Circuit breaker: if all keys timeout, return error fast

### 14. Implement AIGatewayMetrics
- [ ] Create `app/gateway/ai/gateway_metrics.rb`
- [ ] Prometheus metrics:
  - `ai_request_duration_seconds` (histogram by provider, model)
  - `ai_requests_total` (counter by provider, status)
  - `ai_tokens_used_total` (counter by provider)
  - `ai_cost_usd_total` (counter)
  - `ai_provider_available` (gauge)
  - `ai_key_quarantined` (gauge)
- [ ] Cost tracking: estimate from tokens * model pricing

### 15. Write Tests for Failover Scenarios
- [ ] Create `spec/gateway/ai_gateway_spec.rb`
- [ ] Mock all providers with `WebMock`
- [ ] Test scenarios:
  - Primary key rate limited → failover to secondary
  - Primary key 5xx → retry → failover
  - All keys fail → graceful error
  - Latency-based routing picks fastest
  - Cooldown respects quarantine period
  - Health monitor marks/unmarks correctly
  - Cost tracking accuracy

---

## Acceptance Criteria
- [ ] Gateway routes requests in < 5ms overhead
- [ ] Failover on 429/5xx within 1 retry
- [ ] Tier priority respected (cloud > local)
- [ ] Rate limits enforced per key
- [ ] Quarantine/cooldown works correctly
- [ ] Health monitor detects provider issues
- [ ] Metrics exposed for all providers
- [ ] Cost tracking within 10% of actual
- [ ] Tests cover all failover paths

---

## Notes
- AI Gateway is used by AI Agents (Phase 7.2), NOT by trading engines
- Trading engines are deterministic; AI validates/interprets only
- Local Ollama provides zero-cost fallback during cloud outages
- Key rotation spreads load across multiple API keys
- Consider: request caching for repeated prompts (Phase 7.3)
- Model selection: 70b for complex analysis, 8b for simple tasks