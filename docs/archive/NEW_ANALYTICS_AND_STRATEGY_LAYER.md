# New Analytics & Strategy Layer — What It Is and How to Use It

Reference for the files added in the strategy/analytics/context/execution layer. This doc is derived from actual code only.

---

## 1. Domain & Context

### `app/models/domain/trading_context.rb` — `Domain::TradingContext`

**Purpose:** Value object for a single point-in-time trading context (day type, session, regime, score, stability).

**Attributes:** `day_type`, `session`, `regime`, `score`, `stability`.

**Usage:**

```ruby
ctx = Domain::TradingContext.new(
  day_type: :expiry,   # or :normal
  session: :gamma,     # e.g. :gamma, :opening, :midday
  regime: :trend_bull, # :trend_bull, :trend_bear, :chop
  score: 78,
  stability: 5
)
ctx.tradable?  # false if regime == :chop, score < min_score, or stability < 3
ctx.min_score  # 60 for expiry, 50 for normal
```

**Used by:** `Context::Builder`, `Strategy::Registry`, analytics (trade context).

---

### `app/services/context/builder.rb` — `Context::Builder`

**Purpose:** Builds a `Domain::TradingContext` from market data, indicators, and regime state.

**Usage:** `Context::Builder.call(market:, indicators:, regime_state:)`

**Dependencies (wired in signal pipeline):**

- `Market::RegimeScorer` (`app/services/market/regime_scorer.rb`) — adapts `MarketRegimeDetector` to return `{ regime: :trend_bull|:trend_bear|:chop, score: 0–100 }`.
- `Market::SessionResolver.current` (`app/services/market/session_resolver.rb`) — returns `:opening` (09:15–10:30 IST), `:gamma` (14:00–15:15 IST), or `:midday`.
- `Market::RegimeState` — per-index stability and cooldown; used by Scheduler and passed into `Engine.run_for`.
- `expiry_day?` — hard-coded to Thursday for `day_type`.

**Signal pipeline:** `Signal::Scheduler` holds a `RegimeState` per index and passes it to `Signal::Engine.run_for(index_cfg, regime_state:)`. When `signals.enable_trading_context_gate` is true (default), the engine builds `Domain::TradingContext` via `Context::Builder` after primary analysis and blocks signal generation when `context.tradable?` is false (chop, low score, or stability &lt; 3). Exit-testing mode skips the gate.

---

## 2. Strategy Layer

### `app/services/strategy/base.rb` — `Strategy::Base`

**Purpose:** Abstract base for strategies. Subclasses must implement `call(context:, market:, indicators:)`.

### `app/services/strategy/registry.rb` — `Strategy::Registry`

**Purpose:** Resolves which strategy class to use from context.

**Usage:** `Strategy::Registry.resolve(context)`  
Returns: `Strategy::NiftyImpV1`, `Strategy::ExpiryBreakout`, or `nil` based on `[context.day_type, context.session, context.regime]`.

**Gap:** `Strategy::NiftyImpV1` and `Strategy::ExpiryBreakout` are not defined in the repo. Registry will raise `NameError` if you call `resolve` and trigger those constants.

### `app/services/strategy/orchestrator.rb` — `Strategy::Orchestrator`

**Purpose:** Runs multiple strategies, builds context per strategy, asks `Portfolio::Manager` for allocation, then executes via `Orders::Executor`.

**Usage:** `orchestrator.call(market:, indicators:)`  
Expects `@strategies` to be a hash of `{ name => { instance:, regime_state: } }`.

**Note:** `Orders::Executor.call(decision.merge(capital: allocation[:capital]))` is the integration point with your existing order layer (locked infra).

---

## 3. Analytics Layer (Audit Your Edge)

All of these expect **trades** to be an array of hashes with:

- `:pnl` — number
- `:context` — object that responds to `regime`, `session`, `day_type`, `score` (e.g. `Domain::TradingContext` or `OpenStruct`)

If your data has context as a hash, wrap it: `OpenStruct.new(t[:context])` before passing to analytics.

---

### `app/services/analytics/trade_breakdown.rb` — `Analytics::TradeBreakdown`

**Purpose:** Break down performance by regime, session, day type, and score buckets (high ≥70, medium 50–69, low &lt;50).

**Usage:**

```ruby
breakdown = Analytics::TradeBreakdown.new(trades).call
# => {
#   by_regime:   { :trend_bull => { total:, win_rate:, expectancy: }, ... },
#   by_session:  { :gamma => { ... }, ... },
#   by_day_type: { :expiry => { ... }, ... },
#   by_score_bucket: { high: {...}, medium: {...}, low: {...} }
# }
```

---

### `app/services/analytics/threshold_optimizer.rb` — `Analytics::ThresholdOptimizer`

**Purpose:** Find best minimum score threshold (40–90 in steps of 5) by expectancy.

**Usage:**

```ruby
result = Analytics::ThresholdOptimizer.new(trades).call
# => { best_threshold: { threshold:, trades:, win_rate:, expectancy: }, all_results: [...] }
```

---

### `app/services/analytics/metrics.rb` — `Analytics::Metrics`

**Purpose:** Aggregate metrics from trades and an equity curve (for max drawdown).

**Usage:**

```ruby
equity_curve = [] # array of cumulative equity values after each trade
metrics = Analytics::Metrics.new(trades, equity_curve).call
# => { total_trades:, win_rate:, avg_win:, avg_loss:, expectancy:, max_drawdown: }
```

**Note:** `Backtest::Metrics` (in `app/services/backtest/engine.rb`) builds equity from trades and has `win_rate`, `profit_factor`, `max_drawdown` but no `expectancy`. You can build an equity curve from backtest trades and pass it into `Analytics::Metrics` if you want one place for metrics.

---

### `app/services/analytics/strategy_evaluator.rb` — `Analytics::StrategyEvaluator`

**Purpose:** Verdict on whether the strategy is worth running (valid / weak / high_risk / reject) and suggestions.

**Usage:**

```ruby
evaluator = Analytics::StrategyEvaluator.new(trades, metrics_hash).call
# Needs at least 30 trades; else { status: :insufficient_data, message: "..." }
# => { status: {...}, verdict: :valid|:reject|:high_risk|:weak, suggestions: [...] }
```

**Expects:** `metrics_hash` with `:win_rate`, `:expectancy`, `:max_drawdown`. Uses hard-coded `peak_capital` (100_000) for drawdown % checks.

---

### `app/services/analytics/best_setups_extractor.rb` — `Analytics::BestSetupsExtractor`

**Purpose:** Take top 20% of trades by PnL and summarize common regime/session/day_type and average score.

**Usage:**

```ruby
best = Analytics::BestSetupsExtractor.new(trades).call
# => { count:, avg_pnl:, common: { regime:, session:, day_type:, score_avg: } }
```

---

### `app/services/analytics/auto_rule_engine.rb` — `Analytics::AutoRuleEngine`

**Purpose:** Propose rules and position-sizing tiers from best setups + threshold optimizer.

**Usage:**

```ruby
rules = Analytics::AutoRuleEngine.new(trades).call
# => {
#   rules: { allowed_day_type:, allowed_session:, allowed_regime:, min_score: },
#   position_sizing: { high_confidence: {...}, medium_confidence: {...}, low_confidence: {...} }
# }
```

---

### `app/services/analytics/live_adapter.rb` — `Analytics::LiveAdapter`

**Purpose:** Call `AutoRuleEngine` at most once per hour to refresh rules from recent trades.

**Usage:**

```ruby
result = Analytics::LiveAdapter.new(trades: trades, last_updated_at: Time.now - 2.hours).call
# => { rules: AutoRuleEngine output, updated_at: Time.now } or nil if not yet time to update
```

---

## 4. Execution Helpers

- **`Execution::FillValidator`** — `FillValidator.valid?(order_response)` → true if status success and filled_quantity &gt; 0.
- **`Execution::OrderRetry`** — `OrderRetry.call { ... }` → retries block up to 3 times with 0.5s backoff.
- **`Execution::SlippageModel`** — `SlippageModel.apply(price:, side:)` → adds 0.1% slippage (buy: price up, sell: price down).

---

## 5. Market & Risk

- **`Market::RegimeState`** — Tracks current regime and stability (min 3 bars), cooldown after flip (300s). `#update(new_regime)` → `{ regime:, stability:, cooldown: }`.
- **`Portfolio::Manager`** — Allocates capital across strategies from contexts; respects `MAX_TOTAL_RISK`, uses `context.tradable?` and score-based risk.
- **`Risk::LiveGuardrails`** — `#allow_trading?` false if daily drawdown &gt; 5% or last 5 trades all losses.

---

## 6. How This Fits the “Audit My Strategy Edge” Flow

The flow you were given assumes:

1. **Backtest returns** `result` with `result[:trades]` and `result[:metrics]`.
2. **Trades** have `pnl` and `context` (object with `day_type`, `session`, `regime`, `score`).

**Current state in this repo:**

- **`Backtest::Engine`** (`app/services/backtest/engine.rb`) does **not** return a hash. It runs the replayer, fills `@sim.trades`, prints a report, and returns nothing. So you cannot do `result = engine.run; result[:trades]`.
- **Backtest trades** are `{ entry:, exit:, pnl:, entry_time:, exit_time: }` — **no `context`**.
- **Strategy** is a single object with `process(tick)` returning `:buy`/`:exit`/`:none`; there is no `Strategy::Registry` or context-aware strategy in the current backtest loop.

So to run the full audit flow you need one of:

**Option A — Extend the existing backtest (minimal):**

1. In `Backtest::Engine#run`, build a snapshot of “context” at each entry (e.g. from a strategy that receives or computes day_type/session/regime/score from the tick/candles).
2. Append that context to each trade in `TradeSimulator` (e.g. `@trades << { ... }.merge(context: context_at_entry)`).
3. Return `{ trades: @sim.trades, metrics: Backtest::Metrics.new(trades: @sim.trades) }` from `#run`.
4. Build an equity curve from `@sim.trades` if you want `Analytics::Metrics` max_drawdown.

**Option B — Separate “strategy backtest” that uses Context::Builder + Registry:**

1. Implement `Market::RegimeScorer` and `Market::SessionResolver` (or adapt `Market::MarketRegimeResolver` and a session helper to the symbols Registry expects).
2. Define `Strategy::NiftyImpV1` and `Strategy::ExpiryBreakout` (or stub them).
3. Run a backtest that, on each tick, builds context via `Context::Builder`, resolves strategy with `Strategy::Registry.resolve(context)`, runs the strategy, and records trades with that context attached.
4. Then pass those trades into `TradeBreakdown`, `ThresholdOptimizer`, `Metrics`, `StrategyEvaluator`, and `AutoRuleEngine` as above.

---

## 7. Quick “Audit” Without a Full Backtest

If you already have **live or exported trades** with PnL and context:

1. Normalize each trade to `{ pnl: number, context: object with .regime, .session, .day_type, .score }` (e.g. hash → `OpenStruct`).
2. Build equity curve if you want `Analytics::Metrics` (e.g. `cumulative = 0; equity_curve = trades.map { |t| cumulative += t[:pnl] }`).
3. Run:

```ruby
trades = [...] # >= 30 trades, each with :pnl and :context
equity_curve = trades.map.with_index { |t, i| trades[0..i].sum { |x| x[:pnl] } }
metrics = Analytics::Metrics.new(trades, equity_curve).call
breakdown = Analytics::TradeBreakdown.new(trades).call
optimizer = Analytics::ThresholdOptimizer.new(trades).call
evaluator = Analytics::StrategyEvaluator.new(trades, metrics).call
rules = Analytics::AutoRuleEngine.new(trades).call
```

Use `breakdown` for edge localization (where you make/lose money), `optimizer` for best score threshold, `evaluator` for verdict and suggestions, and `rules` for concrete filters and position sizing.

---

## 8. Docs & Scripts

- **`docs/AGENT_TASK_TEMPLATE.md`** — Template for agent tasks (SAFE/BUILD/REFACTOR, context, requirements, validation).
- **`docs/GO_LIVE_PLAN.md`** — Go-live checklist and capital deployment plan: Phase 0 (backtest gates) → Phase 1 (paper) → Phases 2–5 (₹50k → ₹5L) with risk rules, kill switches, and daily routine.
- **`AGENT_RULES.md`** — Project rules: deterministic system, backtest == live, Dhan OHLCV only, locked vs allowed paths, failure protocol.
- **`scripts/agent_guard.rb`** — Script that exits 1 if `git diff --name-only origin/main` touches forbidden paths (orders, positions, exit, live, capital). Run before commits/CI to enforce locked layers.

---

## Summary Table

| File | Purpose |
|------|--------|
| `app/models/domain/trading_context.rb` | Trading context value object; `tradable?`, `min_score` |
| `app/services/context/builder.rb` | Build context from market/indicators/regime_state (needs RegimeScorer, SessionResolver) |
| `app/services/strategy/base.rb` | Abstract strategy interface |
| `app/services/strategy/registry.rb` | Map context → NiftyImpV1 / ExpiryBreakout (classes missing) |
| `app/services/strategy/orchestrator.rb` | Multi-strategy loop + portfolio allocation + Orders::Executor |
| `app/services/analytics/trade_breakdown.rb` | Breakdown by regime/session/day_type/score bucket |
| `app/services/analytics/threshold_optimizer.rb` | Best min score threshold by expectancy |
| `app/services/analytics/metrics.rb` | win_rate, expectancy, max_drawdown from trades + equity curve |
| `app/services/analytics/strategy_evaluator.rb` | Verdict + suggestions (needs 30+ trades) |
| `app/services/analytics/best_setups_extractor.rb` | Top 20% trades → common features |
| `app/services/analytics/auto_rule_engine.rb` | Suggested rules + position sizing from best setups + optimizer |
| `app/services/analytics/live_adapter.rb` | Hourly refresh of rules from recent trades |
| `app/services/market/regime_state.rb` | Regime stability and cooldown |
| `app/services/portfolio/manager.rb` | Allocate capital across strategies by context |
| `app/services/risk/live_guardrails.rb` | Daily drawdown and consecutive-loss gates |
| `app/services/execution/*` | Fill validation, retry, slippage |
