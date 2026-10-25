# AI subsystems: roles & overlap analysis

**Audit finding S-002 (P2 overengineering):** "Multiple parallel implementations
of the same subsystem (AI agents, strategies, dashboards, auth)."

This document maps the LLM-driven subsystems in `app/services/`, identifies
true overlap vs. complementary roles, and records the remediation decisions.

## Subsystem inventory

| Path | Files | Lines | Role | Status |
|---|---|---|---|---|
| `app/services/ai/agents/` | 10 | 698 | Advisory multi-agent pipeline (MarketAnalyst → Strategy → Risk → OptionSelector) | Live — `Ai::AgentsCycleJob` (recurring) + `rake ai:agents:run` |
| `app/services/ai/autonomous/` | 3 | 321 | LLM experiment runner with Observe-Think-Act loop | Live — `rake ai:autonomous:optimize` |
| `app/services/ai/calibration/` | 6 | 970 | Weekly automated indicator calibration via LLM (Claude-style prompt → JSON result → apply) | Live — `WeeklyCalibrationJob` (recurring) + `rake ai:calibrate` |
| `app/services/auto_exp/` | 6 | 339 | LLM-driven automated config experiments: plan → backtest → evaluate → apply | Live (manual) — `scripts/autoexp_runner.rb` |
| `app/services/agents/` | ~~1~~ 0 | ~~360~~ 0 | ~~TradingOrchestrator~~ | **Removed** — 0 live callers, 0 specs, 0 scripts |

## What was removed

**`Agents::TradingOrchestrator`** (360 lines) — had zero live callers
outside its own file. The only external reference was a comment in
`config/initializers/ruby_llm_agents.rb` mentioning the class name.
No rake task, no job, no controller invoked it. Removed in this audit.

## What was kept (and why)

The remaining four subsystems look superficially parallel — all four
orchestrate LLM calls against the trading domain — but they serve
distinct, complementary purposes:

1. **`Ai::Agents`** runs continuously (every N minutes via
   `Ai::AgentsCycleJob`) and produces *advisory* output (AgentDecisionLog
   entries). It does not place trades or modify config.

2. **`Ai::Autonomous`** runs on-demand (`rake ai:autonomous:optimize`)
   and produces *concrete parameter suggestions* by running an
   Observe-Think-Act loop against historical data.

3. **`Ai::Calibration`** runs weekly (`WeeklyCalibrationJob`) and
   *applies* approved parameter changes to `config/algo.yml` after
   LLM-driven validation against a backtest dataset.

4. **`AutoExp`** is a manual experimentation harness
   (`scripts/autoexp_runner.rb`) for ad-hoc config-space exploration.
   Not scheduled; invoked by a human when investigating strategy tweaks.

The actual overlap is between (2) and (3) — both produce parameter
suggestions. The difference is that (2) is interactive (rake task,
human-in-the-loop) while (3) is automated (weekly job, applies
automatically). Consolidating them is a design discussion, not a
mechanical refactor.

## What was NOT addressed

- **Strategies** — `app/strategies/` had 4 dead classes removed in
  S-001 batch 6. The remaining 6 are all live (verified by callers in
  `signal/engine.rb`, `BacktestService`, rake tasks).
- **Dashboards** — `sample-dashboard.html` and `unified-dashboard.html`
  removed in S-001 batch 6. The Vite app in `dashboard/` is the live
  frontend.
- **Auth** — Two operator-token controllers (`CircuitBreakerController`,
  `SettingsController`) were unified in behavior by F-001 (both now
  accept token via header only, no query param fallback). They remain
  separate controllers because they guard different operations.

## Recommended follow-up (not in this PR)

- Design discussion: should `Ai::Autonomous` and `Ai::Calibration` merge
  into a single "parameter-tuning" subsystem with two entry points
  (interactive rake + scheduled job)? Both already call into
  `Ai::Calibration::Runner`.
- `AutoExp` is borderline — only invoked by a manual script. If it has
  not been used in 90+ days, consider archiving or deleting.
