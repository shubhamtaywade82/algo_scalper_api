# Dynamic Config Agent (Phase 1) — Design

Date: 2026-08-25
Status: Approved by user (chat), implementing directly.

## Problem

`config/algo.yml` values (capital allocation, risk model, ADX thresholds,
premium bands, SL/TP, trailing, time-regime multipliers) are static. The
codebase already has the pieces of an agentic AI layer — `Ai::Agents::*`
(advisor-only, never mutates config), `Ai::Calibration::*` (Ollama-driven,
human must call `CalibrationRun#apply!`), `AlgoConfig::DocumentStore`
(DB-backed override layer `AlgoConfig.fetch` already deep-merges over the
YAML) — but nothing closes the loop: no agent reads live market
regime + option chain state and auto-applies a config patch.

## Scope

**In scope (this spec):** a new agent that runs every 15 min (existing
`Ai::AgentsCycleJob` cron), reads live regime + option-chain + risk state,
asks Ollama for a patch across an explicit parameter allow-list, and
applies it to `AlgoConfig::DocumentStore` with no human step. Affects
**new entries only** (existing `Positions::ExitConfigResolver` pins config
at entry — untouched by this spec).

**Explicitly out of scope, future spec:** pushing updated exit/trailing
params onto already-open positions. That needs a mechanism into
`ExitEngine`/`TrailingEngine`/live `PositionTracker`, which is a
materially different (and materially riskier) change from writing to
`DocumentStore`.

**Parameter allow-list for this phase** (per index, `NIFTY`/`BANKNIFTY`/`SENSEX`
unless noted):
- `indices[].capital_alloc_pct`
- `indices[].risk_model.{base_risk_pct,strong_trend_pct,weak_trend_pct}`
- `indices[].adx_thresholds.{primary_min_strength,confirmation_min_strength}`
- `indices[].premium_band.{min,max}`
- `indices[].cooldown_sec`
- `indices[].trade_limits.max_trades_per_day`
- `risk.{sl_pct,tp_pct}`
- `risk.time_regimes.<regime>.{sl_multiplier,tp_multiplier,allow_entries,min_adx,max_adx}`
- `risk.institutional_trailing.<index>.{early_trigger,breakeven_trigger,activation_trigger,trailing_distance}`

Not in scope: `dhanhq.*`, `broker_fees.*`, `trading_time_restrictions.*`,
`expiry_week_power_trend.*` — deployment/infra gates, not trading judgment.

## Autonomy model

- Auto-apply runs unconditionally once wired — **but** the agent checks
  `AlgoConfig.paper_trading_enabled?` before applying and only writes when
  true. Going live (`paper_trading.enabled: false`) still requires the
  same manual flip it does today; this spec does not touch that gate.
- `Ai::Agents::AgentSupervisor::FORBIDDEN_CAPABILITIES` currently hardcodes
  `apply_config` as never-grantable to any agent. This spec removes
  `apply_config` from that list and grants it to `DynamicConfigAgent`
  only — every other existing agent stays `:advisor`.
- No new value clamps beyond what already exists in this exact codebase
  for this exact problem: `Ai::Calibration::ResultParser::KNOWN_PARAMS`
  already whitelists parameter names + confidence threshold + numeric
  bounds for AI-proposed patches. The new agent reuses that pattern
  (own whitelist, `Ai::DynamicConfig::ResultParser`) rather than
  inventing separate business-judgment limits — this is existing
  prior art in the codebase, not a new restriction being imposed.
- `place_order`, `cancel_order`, `modify_order`, `modify_risk_limit`,
  `trip_circuit_breaker` remain forbidden to every agent, including this
  one. Nothing here can execute a trade or touch the circuit breaker.

## Components

New, under `app/services/ai/dynamic_config/`:
- `ContextBuilder` — per index_key: `MarketContext::RegimeComposer` snapshot
  (15m series) + `Options::ChainAnalyzer` ATM CE/PE `analyze_strike`
  (IV, liquidity, greeks) + today's `RiskManagementAgent`-style risk state
  (circuit breaker status, today PnL, consecutive losses) + the current
  allow-listed config slice (so the prompt can show current → propose new).
- `PromptBuilder` — same shape as `Ai::Calibration::PromptBuilder`, injects
  `ContextBuilder` output instead of a historical trade dataset. Instructs
  the model to output only allow-listed parameter names, per-index scoped.
- `ResultParser` — mirrors `Ai::Calibration::ResultParser`: parses JSON,
  whitelist-checks parameter names against the allow-list above, checks a
  numeric bound per parameter, filters by confidence (reuse
  `MIN_CONFIDENCE = 0.70`), builds a deep-mergeable patch hash.

New, under `app/services/ai/agents/`:
- `DynamicConfigAgent < BaseAgent` — `AUTHORITY_LEVEL = :level_2` (new
  constant; `BaseAgent#run`/`log_decision` unchanged, just a different
  value logged). `#perform(index_key:)`: build context → build prompt →
  `Services::Ai::OllamaClient#generate` (schema-enforced, new
  `config/ai_dynamic_config_schema.json`) → parse → if patch present and
  `AlgoConfig.paper_trading_enabled?`, call
  `AlgoConfig::DocumentStore.apply_deep_merge_patch!(patch, source:
  'dynamic_config_agent', actor: 'dynamic_config_agent')`.

Modified:
- `Ai::Agents::AgentSupervisor` — drop `apply_config` from
  `FORBIDDEN_CAPABILITIES`, add it to a new `LEVEL_2_CAPABILITIES` set
  scoped to `dynamic_config_agent` only; `AGENT_NAMES` gains
  `dynamic_config_agent`; `authority_level` returns `:level_2` for it,
  `:advisor` for the rest (currently hardcoded to always return
  `:advisor` — needs a per-agent branch).
- `Ai::Agents::Orchestrator#run_cycle` — add
  `results[:"dynamic_config_#{index_key}"] = DynamicConfigAgent.new.run(index_key: index_key)`
  per index.
- `AlgoConfig::DocumentStore.persist!` — call
  `CacheBroadcaster.publish!(source:)` after `Setting.put` (currently
  dead code — the subscriber starts in the initializer but nothing ever
  publishes). One line, fixes existing cross-process staleness beyond
  the 30s TTL for every writer, not just this new agent.

## Data flow

```
AgentsCycleJob (15min cron, existing)
  → Ai::Agents::Orchestrator#run_cycle
    → DynamicConfigAgent#run(index_key:)
      → ContextBuilder.call(index_key:)          # regime + chain + risk snapshot
      → PromptBuilder.call(context:)              # allow-listed prompt
      → OllamaClient#generate(schema: ...)         # Ollama call, schema-enforced
      → ResultParser.call(raw)                     # whitelist + bounds + confidence filter
      → (if patch present && paper mode)
        → AlgoConfig::DocumentStore.apply_deep_merge_patch!
          → Setting.put + AlgoConfigChangeLog.create!  # existing audit trail
          → AlgoConfig.reset! + CacheBroadcaster.publish!
      → BaseAgent#log_decision → AgentDecisionLog row  # existing audit trail
```

## Error handling

- Ollama unreachable/disabled (`OllamaClient#enabled?` false) → `generate`
  returns nil → agent logs a `no_data`-style decision, no patch, no raise.
  Matches existing `Ai::Calibration::Runner#call_ai_generate` pattern.
- Malformed/unparseable JSON, or every suggested param fails whitelist or
  confidence → `ResultParser` returns an empty patch → agent logs and
  skips the `apply_deep_merge_patch!` call entirely (no empty-hash write).
- `apply_deep_merge_patch!` itself never raises for a validation reason
  today (no validator wired into it) — this spec does not change that;
  the whitelist/bounds gate lives entirely in `ResultParser`, same as
  the existing calibration pipeline. `AlgoConfig::Validator` and its
  RULES-based checking are unrelated dead code, out of scope here.
- Any `StandardError` anywhere in `#perform` is caught by `BaseAgent#run`
  already (existing behavior) and logged as an error decision — the
  15-min cron cadence means a single failed cycle just tries again next
  cycle.

## Testing

- `spec/services/ai/dynamic_config/context_builder_spec.rb` — stub
  `RegimeComposer`/`ChainAnalyzer`, assert shape.
- `spec/services/ai/dynamic_config/result_parser_spec.rb` — whitelist
  rejection, bounds rejection, confidence rejection, valid patch shape.
- `spec/services/ai/agents/dynamic_config_agent_spec.rb` — stub
  `OllamaClient#generate`, assert `DocumentStore.apply_deep_merge_patch!`
  called only when patch present and paper mode true; assert NOT called
  when `paper_trading.enabled: false`.
- `spec/services/ai/agents/agent_supervisor_spec.rb` — extend existing
  spec: `dynamic_config_agent` gets `apply_config`, no other agent does.
- One live-Ollama smoke check (not part of the CI suite — run manually
  against the local Ollama instance per the user's request) exercising
  `DynamicConfigAgent.new.run(index_key: 'NIFTY')` end-to-end and
  printing the resulting patch + whether it applied.

## Self-review notes

- Scope check: touches 3 new files + 4 modified files. Single
  implementation plan, no decomposition needed beyond what's already
  split out (Phase 2 = live position override, separate spec).
- Ambiguity check: "no clamps" (user's autonomy answer) is reconciled
  above — reusing the existing `ResultParser` whitelist/bounds pattern,
  not inventing new restrictions; called out explicitly rather than
  silently applied.
- No placeholders/TBDs remaining.
