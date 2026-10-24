# Algo Scalper API — Detailed Remediation Plan

> **Scope**: Single-user personal trading system | **Stack**: Rails 8 + SolidJS + Node.js sidecar + PostgreSQL + Redis | **Broker**: DhanHQ | **Repo**: `shubhamtaywade82/algo_scalper_api`
>
> **Context adjustment**: This plan is written for a **single-user system running on personal hardware**. Network-access security (CORS, DNS rebinding, auth bypass, WebSocket auth) is de-prioritized since the attack surface is limited to localhost or a personal LAN. Core trading logic bugs that can **lose real money** remain top priority regardless of deployment context.

---

## Priority Re-Calibration for Single-User / Personal System

| Original Severity | Issue | Re-Calibrated Priority | Rationale |
| --- | --- | --- | --- |
| CRITICAL | Redis failure disables all risk limits | **P0 — Fix First** | Directly causes unbounded capital loss even for one user |
| CRITICAL | Smc::Runner syntax error | **P0 — Fix First** | Entire class fails to load; no SMC signals = no trades |
| CRITICAL | Exit poster paren bug | **P0 — Fix First** | Paper trading check is broken; real money may trade when paper mode intended |
| CRITICAL | Undefined `momentum_score` on short path | **P0 — Fix First** | Silent data corruption in short-selling signals |
| CRITICAL | Live execution hangs forever | **P0 — Fix First** | Process hangs, OOM crash, missed exits |
| CRITICAL | Order claim leak (no `ensure`) | **P0 — Fix First** | Permanently blocks order IDs for 20 min each |
| HIGH | Auth fails open | **P3 — Low** | Single user on personal system; no external attackers |
| HIGH | Broker token exposure | **P3 — Low** | Same — localhost/LAN only |
| HIGH | CORS wildcard | **P3 — Low** | No cross-origin risk on personal system |
| HIGH | DNS rebinding (hosts commented out) | **P3 — Low** | Not exposed to public DNS |
| HIGH | StrongParameters `permit!` | **P3 — Low** | No multi-user injection risk |
| HIGH | WebSocket no auth | **P3 — Low** | Single user, personal network |
| HIGH | ActiveCache defaults CE | **P1 — Fix Early** | PE positions may never trigger stop-loss |
| HIGH | Thread#kill shutdown | **P1 — Fix Early** | Can orphan exit orders in-flight |
| HIGH | Reconciliation rapid-fire exit loop | **P2 — Fix Soon** | Can spam broker API, rate limits |
| INFRA | Kamal placeholder IP | **P2 — Fix Soon** | Deployment will fail as-is |
| INFRA | Hardcoded risk limits in sidecar | **P1 — Fix Early** | Desync from Rails config = wrong limits applied |

---

## Phase 0: Pre-Flight (30 minutes)

Before touching any code, set up safety rails.

### 0.1 Create a Git Branch

```bash
git checkout -b fix/remediation-phase1
git push -u origin fix/remediation-phase1
```

### 0.2 Verify Test Suite Baseline

```bash
# Rails tests
cd /path/to/algo_scalper_api
bundle exec rspec 2>&1 | tee baseline_rspec.txt

# Node sidecar tests
cd node-sidecar
npm test 2>&1 | tee baseline_npm_test.txt
```

Record pass/fail counts. Every fix must maintain or improve these numbers.

### 0.3 Enable Paper Trading Mode

Ensure `config/algo_config.yml` has:

```yaml
paper_trading:
  enabled: true
```

**Do not fix anything with real money until all P0s are resolved and validated in paper mode.**

---

## Phase 1: P0 — Critical Trading Logic Bugs (Day 1–2)

These bugs can directly lose you money. Fix them in order.

---

### Fix 1.1: Redis Failure Silently Disables ALL Risk Limits

**File**: `app/services/risk/limits_guard.rb` (lines 64–76)
**Severity**: P0 | **Effort**: 15 min

**Problem**: When Redis is unreachable, `redis` method returns `nil`. Then `nil.to_i` evaluates to `0`, so `0 >= limit` is always `false`. Every risk limit check (max daily trades, max position size, max loss) silently passes.

```ruby
# CURRENT (BROKEN)
def redis
  @redis ||= Redis.new(url: REDIS_URL, timeout: 1, reconnect_attempts: 1)
rescue StandardError => e
  nil  # Redis failure returns nil
end

def max_trades_reached?(limit)
  redis&.get(trades_count_key).to_i >= limit
  # nil.to_i = 0 → 0 >= 10 = false → LIMIT DISABLED
end
```

**Fix**: Fail CLOSED — when Redis is down, block all new trades.

```ruby
# FIXED
def redis
  @redis ||= Redis.new(url: REDIS_URL, timeout: 1, reconnect_attempts: 1)
rescue StandardError => e
  Rails.logger.error("[LimitsGuard] Redis unreachable: #{e.message}")
  @redis_unavailable = true
  nil
end

def redis_available?
  !@redis_unavailable && redis.present?
end

def max_trades_reached?(limit)
  unless redis_available?
    Rails.logger.warn("[LimitsGuard] Redis unavailable — FAILING CLOSED: blocking new trades")
    return true  # Block all new trades when Redis is down
  end
  redis.get(trades_count_key).to_i >= limit
end
```

**Apply the same pattern** to every other limit method in this file (`max_loss_reached?`, `max_position_size_reached?`, etc.). Every method that queries Redis for a risk limit must fail closed.

**Test**:

```ruby
# spec/services/risk/limits_guard_spec.rb
RSpec.describe Risk::LimitsGuard do
  describe '#max_trades_reached?' do
    context 'when Redis is unreachable' do
      before { allow_any_instance_of(Redis).to receive(:get).and_raise(Redis::CannotConnectError) }

      it 'returns true (blocks trades) when Redis is down' do
        guard = described_class.new(trade_params)
        expect(guard.send(:max_trades_reached?, 10)).to be true
      end
    end
  end
end
```

**Rollback**: Revert the commit. The old behavior (fail open) is dangerous but won't break existing functionality.

---

### Fix 1.2: Smc::Runner Syntax Error Prevents Class Loading

**File**: `app/services/smc/runner.rb` (line 207)
**Severity**: P0 | **Effort**: 2 min

**Problem**: Missing closing parenthesis. This prevents the **entire** `Smc::Runner` class from loading. If SMC (Smart Money Concepts) analysis is part of your signal pipeline, you're flying blind on that dimension.

```ruby
# CURRENT (BROKEN) — line 207
[(cp * 0.6).round(2), (cp - (cp * 0.2).round(2)].max
#                                  ^ MISSING )
```

**Fix**:

```ruby
# FIXED
[(cp * 0.6).round(2), (cp - (cp * 0.2)).round(2)].max
```

**Verification**:

```bash
# In Rails console
ruby -c app/services/smc/runner.rb
# Should output: Syntax OK

# Or in Rails console:
rails c
Smc::Runner  # Should load without error
```

**Test**: Add a unit test that instantiates `Smc::Runner` and calls the method containing this line with known inputs.

---

### Fix 1.3: Exit Poster Parentheses Misplaced

**File**: `app/services/ledger/exit_poster.rb` (line 95)
**Severity**: P0 | **Effort**: 2 min

**Problem**: The `dig` call's second argument includes `== true` inside the key path. This means `dig(:paper_trading, :enabled == true)` evaluates `:enabled == true` which is `false` (symbol is never equal to boolean true), so it actually calls `dig(:paper_trading, false)` which returns `nil`. The paper trading check always evaluates to falsy.

```ruby
# CURRENT (BROKEN) — line 95
AlgoConfig.fetch.dig(:paper_trading, :enabled == true
# The == true is INSIDE the dig call
```

**Fix**:

```ruby
# FIXED
AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
```

**Impact**: If you intended to run in paper trading mode, this bug means the system was treating everything as live trading. Check your `config/algo_config.yml` — if `paper_trading.enabled: true` was set, your fills were NOT being paper-traded.

**Verification**:

```bash
rails c
AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
# Should return true/false based on your config
```

---

### Fix 1.4: Undefined `momentum_score` on Short-Selling Path

**File**: `app/services/signal/engine.rb` (line 493, root cause at line 362)
**Severity**: P0 | **Effort**: 30 min

**Problem**: `momentum_score` is only assigned inside the long-bias branch (line 362). When the short-selling path is taken, `momentum_score` is never assigned. At line 493, the code references `momentum_score` but gets `nil`. The enclosing `rescue StandardError` at line 548 silently swallows the resulting `NoMethodError` on `nil`, producing a corrupted or nil signal.

```ruby
# CURRENT (BROKEN) — simplified structure
if long_conditions
  momentum_score = calculate_momentum(...)  # line 362 — only assigned here
  # ... long signal logic
end

# ... later, line 493 (OUTSIDE the if block):
signal.momentum_score = momentum_score  # nil if short path taken
```

**Fix**: Initialize `momentum_score` before the conditional, or assign it in both branches.

```ruby
# FIXED — Option A: Initialize before conditional
momentum_score = 0.0  # Default neutral momentum

if long_conditions
  momentum_score = calculate_momentum(...)
  # ... long signal logic
elsif short_conditions
  momentum_score = -calculate_momentum(...)  # Negate for short
  # ... short signal logic
end

# Now momentum_score is always defined
```

```ruby
# FIXED — Option B: Guard at usage (if you can't modify the conditional)
# At line 493:
signal.momentum_score = momentum_score || 0.0
```

**Additionally**, the `rescue StandardError` at line 548 is a code smell. It masks real bugs like this one. Narrow it:

```ruby
# CURRENT (BROKEN)
rescue StandardError => e
  Rails.logger.error("Signal engine failed: #{e.message}")
  nil

# FIXED — narrow the rescue
rescue DhanHQ::ApiError, DhanHQ::TimeoutError => e
  Rails.logger.error("Signal engine broker error: #{e.message}")
  nil
```

**Test**:

```ruby
RSpec.describe Signal::Engine do
  it 'assigns momentum_score on short-selling path' do
    result = described_class.run(market_data: short_bias_data)
    expect(result.momentum_score).not_to be_nil
  end

  it 'does not swallow NoMethodError from nil momentum_score' do
    expect { described_class.run(market_data: short_bias_data) }.not_to raise_error(NoMethodError)
  end
end
```

---

### Fix 1.5: Live Execution Hangs Forever / OOM Risk

**File**: `node-sidecar/src/engines/live.ts` (line 26)
**Severity**: P0 | **Effort**: 1–2 hours

**Problem**: The live execution engine starts a loop but never publishes fill confirmations back to the Rails app. The `asyncIterator` or event loop hangs indefinitely, accumulating unprocessed promises. Over time this leads to OOM (Out of Memory) crashes.

```typescript
// CURRENT (BROKEN) — line 26 area
// Fill confirmations are received but never published to the WebSocket/channel
// The loop hangs waiting for something that never resolves
```

**Fix**: Add a timeout and ensure fill events are always forwarded.

```typescript
// FIXED — node-sidecar/src/engines/live.ts

const FILL_TIMEOUT_MS = 30_000; // 30 seconds — adjust based on broker SLA

async function waitForFill(orderId: string): Promise<FillEvent | null> {
  const timeout = new Promise<null>((resolve) =>
    setTimeout(() => {
      logger.warn(`[LiveEngine] Fill timeout for order ${orderId} after ${FILL_TIMEOUT_MS}ms`);
      resolve(null);
    }, FILL_TIMEOUT_MS)
  );

  const fillPromise = new Promise<FillEvent>((resolve) => {
    const handler = (event: FillEvent) => {
      if (event.orderId === orderId) {
        fillEmitter.off('fill', handler);
        resolve(event);
      }
    };
    fillEmitter.on('fill', handler);
  });

  return Promise.race([fillPromise, timeout]);
}

// In the main execution loop:
const fill = await waitForFill(order.id);
if (fill) {
  publishFillConfirmation(fill); // Always publish to Rails WebSocket
} else {
  logger.error(`[LiveEngine] No fill received for ${order.id}, querying broker status`);
  await reconcileOrderStatus(order.id); // Fallback: query broker directly
}
```

**Also add a circuit breaker** in the main loop to prevent unbounded accumulation:

```typescript
const MAX_CONCURRENT_ORDERS = 10;
let activeOrders = 0;

// Before placing a new order:
if (activeOrders >= MAX_CONCURRENT_ORDERS) {
  logger.error(`[LiveEngine] Throttling: ${activeOrders} orders already in-flight`);
  return; // Skip this signal, wait for fills
}
activeOrders++;

// After fill or timeout:
activeOrders--;
```

**Test**: Write a test that simulates a fill event not arriving within the timeout and verifies the timeout fires and the order is reconciled.

---

### Fix 1.6: Order Claim Leak Without `ensure` Block

**File**: `app/services/orders/placer.rb` (lines 133–145)
**Severity**: P0 | **Effort**: 20 min

**Problem**: Four methods (`buy_ioc_limit!`, `sell_ioc_limit!`, `sell_limit!`, `buy_limit!`) call `claim!` to reserve a `client_order_id`, but if any exception occurs after `claim!` and before the order completes, the claim is never released. The `client_order_id` stays locked for 20 minutes (the claim TTL), blocking all future orders with that ID.

```ruby
# CURRENT (BROKEN)
def buy_ioc_limit!(...)
  claim!(client_order_id)  # Reserves the ID
  response = dhan_client.place_order(...)  # If THIS throws...
  # ... process response
  # claim is NEVER released if we never get here
end
```

**Fix**: Use `ensure` to always release the claim.

```ruby
# FIXED
def buy_ioc_limit!(...)
  claim!(client_order_id)
  response = nil
  begin
    response = dhan_client.place_order(...)
    process_response(response)
  ensure
    release_claim!(client_order_id) unless response&.success?
    # Release only on failure; success means order is placed
  end
  response
end
```

**Apply this pattern to ALL four methods**: `buy_ioc_limit!`, `sell_ioc_limit!`, `sell_limit!`, `buy_limit!`.

**Important nuance**: Only release on failure. On success, the claim should be consumed (not released), because the order ID is now "used" and should not be reused.

**Test**:

```ruby
RSpec.describe Orders::Placer do
  describe '#buy_ioc_limit!' do
    it 'releases claim when broker API throws' do
      placer = described_class.new
      allow(placer).to receive(:dhan_client).and_raise(DhanHQ::ApiError, "timeout")

      expect { placer.buy_ioc_limit!(params) }.to raise_error(DhanHQ::ApiError)
      expect(placer.claim_exists?(params[:client_order_id])).to be false
    end

    it 'does NOT release claim on successful order' do
      # ... mock successful response
      placer.buy_ioc_limit!(params)
      expect(placer.claim_exists?(params[:client_order_id])).to be true # consumed, not released
    end
  end
end
```

---

### Fix 1.7: ActiveCache Defaults CE for Unknown Directions

**File**: `app/services/positions/active_cache.rb` (lines 64–68)
**Severity**: P1 | **Effort**: 10 min

**Problem**: When the option direction cannot be determined (data race, corrupt state, edge case), the code defaults to `"CE"` (Call European). If the actual position is a PE (Put European), the stop-loss logic will monitor the wrong instrument and may never trigger.

```ruby
# CURRENT (BROKEN) — line 64-68
def option_type
  # ... some logic ...
  "CE"  # DEFAULT FALLBACK
end
```

**Fix**: Fail loudly instead of guessing.

```ruby
# FIXED
def option_type
  # ... existing detection logic ...
  detected = determine_option_type_from_position

  if detected.nil? || detected.empty?
    Rails.logger.error("[ActiveCache] Cannot determine option type for position #{id} " \
                        "— instrument: #{instrument_token}, direction: #{direction}")
    return nil  # Let callers handle the unknown case
  end

  detected
end
```

**Then, in every caller** that uses `option_type`, add a guard:

```ruby
# In stop-loss checker:
opt_type = position.option_type
if opt_type.nil?
  Rails.logger.error("[SL] Skipping SL check — unknown option type for position #{position.id}")
  next
end
```

**Test**: Write a test that creates a position with an unrecognized instrument token and verifies `option_type` returns `nil` (not `"CE"`).

---

### Fix 1.8: Hardcoded Risk Limits in Node Sidecar

**File**: `node-sidecar/src/executor.ts` (lines 51–53)
**Severity**: P1 | **Effort**: 30 min

**Problem**: The Node.js sidecar has its own risk limits hardcoded (`maxQty: 500`, `dailyMaxLoss: 10000`) that are not synced from the Rails configuration. If you change your risk parameters in Rails, the sidecar still uses the old values.

```typescript
// CURRENT (BROKEN) — node-sidecar/src/executor.ts:51-53
const RISK_LIMITS = {
  maxQty: 500,
  dailyMaxLoss: 10000,
};
```

**Fix**: Fetch limits from Rails API on startup and periodically.

```typescript
// FIXED — node-sidecar/src/executor.ts

interface RiskLimits {
  maxQty: number;
  dailyMaxLoss: number;
  maxTradesPerDay: number;
  [key: string]: number;
}

class RiskConfig {
  private limits: RiskLimits;
  private lastFetched: number;
  private readonly REFRESH_INTERVAL_MS = 60_000; // Refresh every minute

  constructor(private railsApiUrl: string) {
    this.limits = { maxQty: 0, dailyMaxLoss: 0, maxTradesPerDay: 0 };
    this.lastFetched = 0;
  }

  async get(): Promise<RiskLimits> {
    if (Date.now() - this.lastFetched > this.REFRESH_INTERVAL_MS) {
      await this.refresh();
    }
    return this.limits;
  }

  private async refresh(): Promise<void> {
    try {
      const resp = await fetch(`${this.railsApiUrl}/api/v1/settings/risk_limits`, {
        headers: { Authorization: `Bearer ${process.env.RAILS_API_TOKEN}` },
      });
      if (resp.ok) {
        this.limits = await resp.json();
        this.lastFetched = Date.now();
        logger.info(`[RiskConfig] Refreshed limits: ${JSON.stringify(this.limits)}`);
      }
    } catch (err) {
      logger.error(`[RiskConfig] Failed to fetch limits, using cached: ${err}`);
      // Use last known good values — don't fail closed here
      // because Rails is the source of truth, not the sidecar
    }
  }
}
```

**On the Rails side**, add an endpoint (if not present):

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    get 'settings/risk_limits', to: 'settings#risk_limits'
  end
end

# app/controllers/api/settings_controller.rb
def risk_limits
  config = AlgoConfig.fetch
  render json: {
    max_qty: config.dig(:risk, :max_qty) || 50,
    daily_max_loss: config.dig(:risk, :daily_max_loss) || 5000,
    max_trades_per_day: config.dig(:risk, :max_trades_per_day) || 10,
  }
end
```

---

## Phase 2: P1 — Reliability Fixes (Day 3–4)

---

### Fix 2.1: Thread#kill Shutdown Risk

**File**: `app/services/live/risk_manager_service.rb` (line 92)
**Severity**: P1 | **Effort**: 1 hour

**Problem**: `Thread#kill` is used to shut down monitoring threads. This is violent termination — it doesn't run `ensure` blocks, doesn't release locks, and can leave exit orders in-flight (submitted to broker but never confirmed in the local database).

```ruby
# CURRENT (BROKEN)
def shutdown
  @thread&.kill  # Violent termination
end
```

**Fix**: Use a graceful shutdown flag.

```ruby
# FIXED
class Live::RiskManagerService
  def initialize
    @shutdown_flag = false
    @thread = nil
    @mutex = Mutex.new
  end

  def start
    @thread = Thread.new do
      loop do
        break if @shutdown_flag

        @mutex.synchronize { run_cycle }

        sleep(poll_interval)
      end
      # Thread exits naturally — all ensure blocks run
    ensure
      cleanup_in_flight_exits
      Rails.logger.info("[RiskManager] Thread shut down gracefully")
    end
  end

  def shutdown
    @shutdown_flag = true
    @thread&.join(10)  # Wait up to 10 seconds for graceful exit
    if @thread&.alive?
      Rails.logger.warn("[RiskManager] Thread did not shut down in 10s, forcing")
      @thread.kill  # Last resort only
    end
  end

  private

  def cleanup_in_flight_exits
    # Check for any exit orders submitted to broker but not confirmed
    # Reconcile with broker before shutdown
    ReconciliationService.reconcile_pending_exits
  end
end
```

---

### Fix 2.2: Reconciliation Rapid-Fire Exit Loop

**File**: `app/services/live/reconciliation_service.rb` (lines 173–195)
**Severity**: P2 | **Effort**: 30 min

**Problem**: When an exit order is stuck (e.g., broker shows "open" but locally it should be "filled"), the reconciliation service may repeatedly attempt to exit the same position, creating a loop that spams the broker API and risks rate limits.

**Fix**: Add a cooldown and attempt counter.

```ruby
# FIXED — app/services/live/reconciliation_service.rb

RECONCILIATION_COOLDOWN_SECONDS = 60
MAX_EXIT_ATTEMPTS = 3

def reconcile_position(position)
  cache_key = "reconcile_exit_attempt:#{position.id}"

  attempt_count = Redis.current.incr(cache_key)
  Redis.current.expire(cache_key, 3600) # 1 hour TTL

  if attempt_count > MAX_EXIT_ATTEMPTS
    Rails.logger.error("[Reconciliation] Position #{position.id} exceeded #{MAX_EXIT_ATTEMPTS} exit attempts. " \
                        "Manual intervention required. Marking as orphaned.")
    position.update!(status: :orphaned, reconciliation_note: "Exceeded max exit attempts")
    send_alert("Position #{position.id} orphaned after #{attempt_count} exit attempts")
    return
  end

  last_attempt_key = "reconcile_exit_last:#{position.id}"
  last_attempt = Redis.current.get(last_attempt_key)

  if last_attempt && (Time.current - Time.parse(last_attempt)) < RECONCILIATION_COOLDOWN_SECONDS
    Rails.logger.info("[Reconciliation] Skipping position #{position.id} — cooldown active")
    return
  end

  Redis.current.set(last_attempt_key, Time.current.iso8601, ex: RECONCILIATION_COOLDOWN_SECONDS + 10)

  # ... existing reconciliation logic ...
end
```

---

### Fix 2.3: Kamal Deployment Placeholder

**File**: `config/deploy.yml` (line 8)
**Severity**: P2 | **Effort**: 5 min

**Problem**: The server address is a placeholder `192.168.0.1`. Deployment will fail.

```yaml
# CURRENT (BROKEN)
servers:
  - 192.168.0.1
```

**Fix**: Update to your actual server IP or localhost.

```yaml
# FIXED
servers:
  - <%= ENV["DEPLOY_SERVER"] || "192.168.1.100" %>
```

Set the `DEPLOY_SERVER` environment variable in your `.env` or `deploy.env`.

---

## Phase 3: P3 — Security Hardening (Day 5–6)

> These are low priority for a single-user personal system. Fix them when convenient, but they won't lose you money.

---

### Fix 3.1: Token Auth Fails Open

**File**: `app/controllers/concerns/api/token_authenticatable.rb` (lines 21–23)

```ruby
# CURRENT
def require_api_token!(expected, tier:)
  expected = expected.presence
  return if expected.blank?  # Skips ALL auth when env var not set
```

**Fix** (for personal system, just ensure the env var is set):

```ruby
# FIXED
def require_api_token!(expected, tier:)
  expected = expected.presence
  if expected.blank?
    if Rails.env.production?
      Rails.logger.warn("[Auth] API token not configured for #{tier} tier in production")
      # In production, fail closed
      render json: { error: "Server misconfigured: auth token missing" }, status: :internal_server_error
      return
    end
    # In development, allow without token
    return
  end
  # ... rest of auth logic
end
```

### Fix 3.2: Broker Token Exposure

**File**: `app/controllers/api/dhan_access_token_controller.rb`

Even for a personal system, don't expose raw broker tokens. At minimum, mask them in logs.

```ruby
# Add to the controller or a concern
filter_parameter_logging :access_token, :dhan_token
```

### Fix 3.3: CORS Wildcard

**File**: `config/initializers/cors.rb` (lines 15–17)

```ruby
# CURRENT
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "*") # Falls back to * in production
```

**Fix**: Set the env var properly.

```bash
# .env
CORS_ORIGINS=http://localhost:3000,http://localhost:5173
```

### Fix 3.4: StrongParameters `permit!`

**File**: `app/controllers/api/settings_controller.rb` (lines 36, 114)

```ruby
# CURRENT
params.permit!  # Allows everything
```

**Fix**: Explicitly permit only known fields.

```ruby
# FIXED
def settings_params
  params.require(:settings).permit(
    :max_trades_per_day, :max_position_size, :max_daily_loss,
    :default_sl_points, :default_tp_points, :trail_activation_points,
    :trail_interval_points, risk_limits: {}
  )
end
```

### Fix 3.5: WebSocket Auth

**File**: `app/channels/application_cable/connection.rb` (lines 17–19)

For a personal system, just ensure the token is required in production:

```ruby
# FIXED
def connect
  if Rails.env.production?
    token = request.params[:token]
    if token != ENV.fetch("DASHBOARD_TOKEN", nil)
      reject_unauthorized_connection
      return
    end
  end
  # In development, allow all connections
end
```

---

## Phase 4: Testing & Validation (Day 7–8)

---

### 4.1 Unit Tests (Must-Have)

Create test files for every P0/P1 fix:

| Fix | Test File | Key Test Cases |
| --- | --- | --- |
| 1.1 Redis fail-closed | `spec/services/risk/limits_guard_spec.rb` | Redis down → blocks trades; Redis up → normal behavior |
| 1.2 SMC syntax | `spec/services/smc/runner_spec.rb` | Class loads; method returns correct value |
| 1.3 Exit poster | `spec/services/ledger/exit_poster_spec.rb` | Paper mode check returns correct boolean |
| 1.4 Momentum score | `spec/services/signal/engine_spec.rb` | Short path assigns momentum_score; no NoMethodError |
| 1.6 Claim leak | `spec/services/orders/placer_spec.rb` | Claim released on exception; claim consumed on success |
| 1.7 ActiveCache | `spec/services/positions/active_cache_spec.rb` | Unknown direction → returns nil, not "CE" |
| 2.1 Thread shutdown | `spec/services/live/risk_manager_service_spec.rb` | Graceful shutdown within timeout |
| 2.2 Reconciliation | `spec/services/live/reconciliation_service_spec.rb` | Cooldown respected; max attempts triggers orphan |

### 4.2 Integration Tests

```ruby
# spec/integration/trading_pipeline_spec.rb
RSpec.describe "Trading Pipeline Integration" do
  it 'places an order and processes fill in paper mode' do
    # Start with paper trading enabled
    # Generate a signal
    # Verify order is placed
    # Simulate fill
    # Verify position is opened
    # Trigger exit condition
    # Verify exit order is placed
    # Simulate exit fill
    # Verify position is closed and ledger is updated
  end

  it 'respects risk limits even when Redis is flaky' do
    # Mock Redis to fail intermittently
    # Verify trades are blocked during Redis outages
  end
end
```

### 4.3 Paper Trading Validation (Minimum 5 Trading Days)

Before going live with real capital, run the system in paper trading mode for at least 5 full trading days.

**Validation Checklist**:

- [ ] System starts without errors
- [ ] SMC Runner loads and processes market data
- [ ] Signals are generated for both long and short paths
- [ ] `momentum_score` is populated in all signals
- [ ] Orders are placed with correct `client_order_id`
- [ ] Claims are released on failed orders
- [ ] ActiveCache correctly identifies CE vs PE positions
- [ ] Stop-loss triggers for BOTH CE and PE positions
- [ ] Trailing stop activates and trails correctly
- [ ] Exit orders are placed and processed
- [ ] Ledger entries are balanced (double-entry)
- [ ] Reconciliation does not create rapid-fire exit loops
- [ ] Risk limits are enforced (max trades, max loss, max position size)
- [ ] Redis outage blocks new trades
- [ ] System shuts down gracefully (no orphaned orders)
- [ ] Daily P&L report matches manual calculation
- [ ] Node sidecar stays under 500MB memory after 6 hours

### 4.4 Go-Live Checklist

- [ ] All P0 fixes merged and tested
- [ ] All P1 fixes merged and tested
- [ ] Paper trading completed for 5+ days with no critical errors
- [ ] `paper_trading.enabled` set to `false` in `algo_config.yml`
- [ ] `DASHBOARD_TOKEN` env var set for production
- [ ] `CORS_ORIGINS` env var set (restrict to your IP)
- [ ] `DEPLOY_SERVER` set to actual server IP
- [ ] Redis monitored (alert on downtime)
- [ ] Log rotation configured
- [ ] Database backups configured
- [ ] Kill switch tested (can you stop all trading instantly?)
- [ ] Broker API rate limits verified (not being hit)

---

## Implementation Order & Dependencies

```
Phase 0: Pre-flight
  ├── git branch, test baseline, paper mode
  └── No dependencies

Phase 1: P0 Critical (parallel-safe, order doesn't matter much)
  ├── Fix 1.2 (syntax) —— 2 min, no deps
  ├── Fix 1.3 (paren) —— 2 min, no deps
  ├── Fix 1.1 (Redis fail-closed) — 15 min, no deps
  ├── Fix 1.4 (momentum_score) — 30 min, no deps
  ├── Fix 1.6 (claim leak) — 20 min, no deps
  ├── Fix 1.7 (ActiveCache CE default) — 10 min, no deps
  ├── Fix 1.8 (hardcoded sidecar limits) — 30 min, depends on Rails endpoint
  └── Fix 1.5 (live hang/OOM) — 1-2 hrs, most complex

Phase 2: P1 Reliability
  ├── Fix 2.1 (Thread#kill) — 1 hr, no deps
  ├── Fix 2.2 (reconciliation loop) — 30 min, needs Redis
  └── Fix 2.3 (Kamal placeholder) — 5 min, no deps

Phase 3: P3 Security (do when convenient)
  ├── Fix 3.1 (auth fail-open)
  ├── Fix 3.2 (token exposure)
  ├── Fix 3.3 (CORS)
  ├── Fix 3.4 (permit!)
  └── Fix 3.5 (WebSocket auth)

Phase 4: Testing & Validation
  ├── 4.1 Unit tests (write alongside each fix)
  ├── 4.2 Integration tests (after all P0/P1)
  ├── 4.3 Paper trading (5+ days)
  └── 4.4 Go-live checklist
```

---

## Summary: Effort Estimate

| Phase | Duration | Fixes | Risk Reduction |
| --- | --- | --- | --- |
| Phase 0 | 30 min | Pre-flight | Baseline established |
| Phase 1 (P0) | 1–2 days | 8 fixes | Eliminates all money-losing bugs |
| Phase 2 (P1) | 1 day | 3 fixes | Eliminates reliability risks |
| Phase 3 (P3) | 1–2 hours | 5 fixes | Hardens for any future multi-user use |
| Phase 4 | 5–8 days | Testing | Validates everything before real capital |
| **Total** | **7–12 days** | **16 fixes** | **System ready for live trading** |

---

## File Change Summary

| File | Fixes Applied | Lines Changed (est.) |
| --- | --- | --- |
| `app/services/risk/limits_guard.rb` | 1.1 | ~15 lines |
| `app/services/smc/runner.rb` | 1.2 | 1 line |
| `app/services/ledger/exit_poster.rb` | 1.3 | 1 line |
| `app/services/signal/engine.rb` | 1.4 | ~10 lines |
| `app/services/orders/placer.rb` | 1.6 | ~20 lines (4 methods) |
| `app/services/positions/active_cache.rb` | 1.7 | ~10 lines |
| `app/services/live/risk_manager_service.rb` | 2.1 | ~30 lines |
| `app/services/live/reconciliation_service.rb` | 2.2 | ~25 lines |
| `node-sidecar/src/engines/live.ts` | 1.5 | ~40 lines |
| `node-sidecar/src/executor.ts` | 1.8 | ~50 lines |
| `config/deploy.yml` | 2.3 | 1 line |
| `app/controllers/concerns/api/token_authenticatable.rb` | 3.1 | ~8 lines |
| `app/controllers/api/dhan_access_token_controller.rb` | 3.2 | ~2 lines |
| `config/initializers/cors.rb` | 3.3 | 0 (env var only) |
| `app/controllers/api/settings_controller.rb` | 3.4 | ~10 lines |
| `app/channels/application_cable/connection.rb` | 3.5 | ~8 lines |
| `config/routes.rb` | 1.8 | ~3 lines |
