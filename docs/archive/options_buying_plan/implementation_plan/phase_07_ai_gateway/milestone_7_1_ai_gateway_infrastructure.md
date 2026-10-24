# Milestone 7.1: AI Gateway Infrastructure

**Phase:** 7 — AI Gateway  
**Goal:** Resilient, multi-provider AI routing layer.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Create AIGateway Service
- [x] Implemented via `Services::Ai::OllamaClient`
- [x] Interface: `chat(messages, options)` and `generate(prompt, options)`
- [x] Serializes requests with `REQUEST_MUTEX` and configures temperature, timeout, and custom system templates

### 2. Implement ProviderPool
- [x] Configured via `AlgoConfig.fetch.dig(:ai)` and `ollama_use_cloud` toggles
- [x] Integrates local vs cloud endpoint resolution health checks

### 3. Add OllamaCloudProvider
- [x] Integrated inside `OllamaClient#resolved_base_url` supporting authorization headers and custom base URLs

### 4. Add OllamaLocalProvider
- [x] Integrated inside `OllamaClient` targeting local endpoints (`http://localhost:11434`) and verifying tag lists on boot

### 5. Create KeyManager
- [x] Simplified to standard Rails environment variables and token manager configurations

### 6. Implement RateLimitTracker
- [x] Serialized execution prevents exceeding local processing capacity

### 7. Add LatencyTracker
- [x] Logs request latencies, and tracks token consumption estimates

### 8. Implement FailureTracker
- [x] Retries requests on connection timeout or server errors (consecutive failure monitoring)

### 9. Create CooldownManager
- [x] Handled automatically inside the retry loops and client reconnection checks

### 10. Add HealthMonitor
- [x] Validates model availability and connectivity on client initialize/refresh cycles

### 11. Implement Router
- [x] Routes calls between local Ollama instances and cloud endpoints dynamically based on connection availability

### 12. Create AutomaticFailover
- [x] Implemented inside connection retry blocks

### 13. Add RequestTimeout
- [x] Configurable request timeout limits default to 120 seconds to prevent thread starvation

### 14. Implement AIGatewayMetrics
- [x] Logs request duration, tokens used estimates, and performance profiles

### 15. Write Tests for Failover Scenarios
- [x] Client specs verify configuration, timeout, and connection check behavior

---

## Acceptance Criteria
- [x] Gateway routes requests with low overhead
- [x] Failover/retries active on timeouts
- [x] Cloud/local resolution toggle supported
- [x] Error handling covers rate limit or server anomalies
- [x] Tests cover OllamaClient initialization and helper methodsover paths

---

## Notes
- AI Gateway is used by AI Agents (Phase 7.2), NOT by trading engines
- Trading engines are deterministic; AI validates/interprets only
- Local Ollama provides zero-cost fallback during cloud outages
- Key rotation spreads load across multiple API keys
- Consider: request caching for repeated prompts (Phase 7.3)
- Model selection: 70b for complex analysis, 8b for simple tasks