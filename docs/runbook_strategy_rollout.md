# Production Runbook: Strategy Engine Rollout & Operations

**Last Updated:** 2025-01-XX
**Status:** Pre-Production
**Owner:** Trading System Team

---

## Table of Contents

1. [Emergency Controls](#emergency-controls)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Canary Deployment Steps](#canary-deployment-steps)
4. [Full Production Rollout](#full-production-rollout)
5. [Monitoring & Alerting](#monitoring--alerting)
6. [Troubleshooting](#troubleshooting)
7. [Rollback Procedures](#rollback-procedures)
8. [Post-Deployment Validation](#post-deployment-validation)

---

## Emergency Controls

### Immediate Stop (30 seconds)

**Option 1: Environment Variable (Fastest)**
```bash
# Set in environment or .env
export DISABLE_TRADING_SUPERVISOR=true
# Restart worker container/service
```

**Option 2: Config Override (No Restart)**
```yaml
# config/algo.yml - set all strategies to disabled
strategy:
  active: null  # or remove strategy section entirely
```

**Option 3: Feature Flag (If Implemented)**
```ruby
# Rails console
AlgoConfig.fetch[:strategy][:active] = nil
# Reload config (if hot-reload supported)
```

**Option 4: Health Endpoint (If Available)**
```bash
curl -X POST http://localhost:3000/api/trading/disable
```

### Verify Stop
```bash
# Check logs for "TradingSupervisor stopped" or "SignalScheduler stopped"
tail -f log/production.log | grep -i "supervisor\|scheduler"
```

---

## Pre-Deployment Checklist

### ✅ Code Readiness

- [ ] All unit tests passing (`bin/rails test`)
- [ ] RSpec suite green (`bundle exec rspec`)
- [ ] RuboCop clean (`bin/rubocop`)
- [ ] Brakeman security scan clean (`bin/brakeman --no-pager`)
- [ ] No linter errors in strategy engine files
- [ ] Integration test: Signal → EntryGuard → Allocator → Paper Gateway

### ✅ Configuration Validation

- [ ] `config/algo.yml` validates (no YAML syntax errors)
- [ ] Strategy configs have valid `multiplier` (integer >= 1)
- [ ] `capital_alloc_pct` values are between 0.0 and 1.0
- [ ] All required fields present: `active`, `direction`, strategy-specific configs
- [ ] Paper trading enabled by default (`paper_trading.enabled: true`)

### ✅ Data Infrastructure

- [ ] Redis connection healthy (`redis-cli ping`)
- [ ] WebSocket feed running (`Live::MarketFeedHub.instance.running?`)
- [ ] Option chain API accessible (test DhanHQ client)
- [ ] Derivative records populated for target indices
- [ ] Tick cache has recent data for test instruments

### ✅ Observability

- [ ] Log aggregation configured (Papertrail/Datadog/etc)
- [ ] Metrics endpoint accessible (`/api/health`)
- [ ] Alerting rules configured (see Monitoring section)
- [ ] Dashboard access granted to team

### ✅ Backtest Validation

- [ ] Backtest run on last 30 days of data
- [ ] Backtest report generated (CSV/JSON)
- [ ] Expectancy > 0 or acceptable risk profile
- [ ] Max drawdown within acceptable limits
- [ ] Win rate > 50% (or strategy-specific threshold)

---

## Canary Deployment Steps

### Phase 1: Single Strategy, Minimal Capital (48-72 hours)

**Goal:** Validate one strategy with 1-2% capital allocation.

**Steps:**

1. **Update `config/algo.yml`:**
```yaml
strategy:
  active: "momentum_buying"  # Start with simplest strategy
  direction: "bullish"

  momentum_buying:
    lot_multiplier: 1  # Minimum multiplier
    min_rsi: 60

indices:
  - key: NIFTY
    capital_alloc_pct: 0.01  # 1% of capital only
    max_same_side: 1
```

2. **Deploy to Staging:**
```bash
# Ensure paper mode
export PAPER_TRADING=true
# Deploy worker container
docker-compose up -d worker
# Or if using Railway/Render, push to staging branch
```

3. **Monitor for 4 hours:**
```bash
# Watch logs
tail -f log/production.log | grep -E "Signal|EntryGuard|Orders::Manager"

# Check metrics
curl http://localhost:3000/api/health

# Verify no errors
grep -i "error\|exception" log/production.log | tail -20
```

4. **Validation Checks:**
- [ ] Signals generated (check logs for `[Signal::Engines::MomentumBuyingEngine]`)
- [ ] EntryGuard passed (check for `[EntryGuard] Successfully placed order`)
- [ ] Allocator calculated qty correctly (check logs for `[Capital::Allocator]`)
- [ ] Orders placed in paper mode (check `PositionTracker.paper.count`)
- [ ] No exceptions or rate limit errors

5. **After 48 hours:**
- [ ] Review all trades in paper mode
- [ ] Check PnL distribution
- [ ] Verify no duplicate orders
- [ ] Confirm cooldown logic working

### Phase 2: Increase Capital (24-48 hours)

**If Phase 1 successful:**

1. **Increase allocation:**
```yaml
indices:
  - key: NIFTY
    capital_alloc_pct: 0.02  # 2% now
```

2. **Monitor for 24 hours**
3. **If stable, proceed to Phase 3**

### Phase 3: Add Second Strategy (48-72 hours)

**If Phase 2 successful:**

1. **Enable second strategy:**
```yaml
strategy:
  active: "open_interest"  # Switch or add priority-based selection
```

2. **Monitor for 48 hours**
3. **Validate both strategies work independently**

---

## Full Production Rollout

### Step 1: Enable All Strategies (Staging)

```yaml
strategy:
  active: "momentum_buying"  # Primary
  direction: "bullish"

  momentum_buying:
    lot_multiplier: 1
  open_interest:
    lot_multiplier: 1
  btst:
    btst_lot_multiplier: 1
  swing:
    swing_lot_multiplier: 1
```

### Step 2: Gradual Capital Increase

**Week 1:** 5% capital allocation
**Week 2:** 10% capital allocation
**Week 3:** 15% capital allocation
**Week 4:** Full allocation (per index config)

### Step 3: Enable Live Trading (After 2 weeks paper success)

```yaml
paper_trading:
  enabled: false  # ⚠️ CRITICAL: Only after extensive paper validation
```

---

## Monitoring & Alerting

### Key Metrics to Track

**Signal Generation:**
- `signals_generated_total` (per strategy)
- `signals_rejected_total` (reason: missing_data, conditions_not_met)
- `strategy_evaluation_duration_ms` (p50, p95, p99)

**Entry Processing:**
- `entry_guard_passed_total`
- `entry_guard_rejected_total` (reason: exposure_limit, cooldown, insufficient_capital)
- `allocator_qty_calculated` (histogram)

**Order Execution:**
- `orders_placed_total` (paper vs live)
- `orders_failed_total` (reason: api_error, timeout, invalid_qty)
- `dhanhq_api_errors_total` (429, 500, timeout)

**System Health:**
- `websocket_connected` (0 or 1)
- `redis_tick_cache_hit_rate` (0.0 to 1.0)
- `option_chain_api_latency_ms` (p95)

### Alert Rules

**Critical (Page On-Call):**
- `orders_failed_total > 5 in 5 minutes` → DhanHQ API issues
- `websocket_connected == 0 for > 2 minutes` → Feed disconnected
- `dhanhq_api_errors_total{status=429} > 3 in 1 minute` → Rate limit hit

**Warning (Notify Team):**
- `signals_rejected_total{reason="missing_data"} > 10 in 10 minutes` → Data quality issue
- `entry_guard_rejected_total{reason="insufficient_capital"} > 5 in 1 hour` → Capital allocation issue
- `strategy_evaluation_duration_ms{p99} > 5000` → Performance degradation

### Log Queries (Example)

**Find all signals generated today:**
```bash
grep "\[Signal::Engines::" log/production.log | grep "$(date +%Y-%m-%d)"
```

**Find all orders placed:**
```bash
grep "\[Orders::Manager\] BUY" log/production.log | tail -20
```

**Find allocation rejections:**
```bash
grep "\[Capital::Allocator\].*qty=0" log/production.log
```

---

## Troubleshooting

### Issue: No Signals Generated

**Symptoms:** Logs show scheduler running but no `[Signal::Engines::*]` entries.

**Diagnosis:**
```ruby
# Rails console
index_cfg = AlgoConfig.fetch[:indices].first
strategy_cfg = AlgoConfig.fetch[:strategy]
analyzer = Options::ChainAnalyzer.new(...)
candidates = analyzer.select_candidates(limit: 1)
# Check if candidates empty
```

**Common Causes:**
- No option chain data (check DhanHQ API)
- No tick data in Redis (check WebSocket feed)
- Strategy conditions not met (check engine logic)

**Fix:**
- Verify WebSocket feed running
- Check option chain API accessible
- Review strategy config thresholds

### Issue: EntryGuard Rejecting All Signals

**Symptoms:** Signals generated but `[EntryGuard] Exposure check failed` or `Cooldown active`.

**Diagnosis:**
```ruby
# Rails console
PositionTracker.active.count
PositionTracker.active.where(side: 'long_ce').count
# Check cooldown cache
Rails.cache.read("cooldown:#{symbol}")
```

**Common Causes:**
- `max_same_side` limit reached
- Cooldown window active
- Insufficient capital

**Fix:**
- Adjust `max_same_side` in config
- Reduce `cooldown_sec` if too aggressive
- Check `Capital::Allocator.available_cash`

### Issue: Allocator Returning 0 Quantity

**Symptoms:** `[Capital::Allocator] Invalid quantity` or `qty=0`.

**Diagnosis:**
```ruby
# Rails console
Capital::Allocator.available_cash
Capital::Allocator.qty_for(
  index_cfg: index_cfg,
  entry_price: 120.0,
  derivative_lot_size: 50,
  scale_multiplier: 1
)
```

**Common Causes:**
- Insufficient capital
- Entry price * lot_size > available capital
- Invalid multiplier (non-integer)

**Fix:**
- Increase paper trading balance (if paper mode)
- Check live balance (if live mode)
- Verify multiplier is integer >= 1

### Issue: DhanHQ Rate Limiting (429 Errors)

**Symptoms:** `[Orders::Placer] BUY failed: 429 Too Many Requests`.

**Diagnosis:**
```bash
grep "429\|rate.*limit" log/production.log | tail -20
```

**Fix:**
- Reduce scheduler frequency (increase `DEFAULT_PERIOD`)
- Implement request throttling (if not present)
- Add exponential backoff in `Orders::Placer`
- Use WebSocket ticks instead of REST API where possible

### Issue: WebSocket Disconnected

**Symptoms:** `[MarketFeedHub] WebSocket disconnected` or `[EntryGuard] WebSocket not connected`.

**Diagnosis:**
```ruby
# Rails console
Live::MarketFeedHub.instance.running?
Live::MarketFeedHub.instance.connected?
```

**Fix:**
- Restart WebSocket feed
- Check network connectivity
- Verify DhanHQ WebSocket endpoint accessible
- System falls back to REST API (should not block trading)

---

## Rollback Procedures

### Immediate Rollback (Strategy Disable)

**Method 1: Config Change**
```yaml
# config/algo.yml
strategy:
  active: null  # Disable all strategies
```

**Method 2: Environment Variable**
```bash
export DISABLE_TRADING_SUPERVISOR=true
# Restart worker
```

### Code Rollback (If Bug Introduced)

```bash
# Git rollback to previous commit
git revert <commit-hash>
# Or
git reset --hard <previous-commit>
# Deploy previous version
```

### Database Rollback (If Needed)

```ruby
# Rails console - Close all positions from new strategies
PositionTracker.active.where("created_at > ?", rollback_time).each do |pt|
  # Exit position logic
end
```

---

## Post-Deployment Validation

### Hour 1 Checklist

- [ ] No exceptions in logs
- [ ] Signals generated (check count)
- [ ] EntryGuard processing signals
- [ ] Orders placed (paper mode)
- [ ] Allocator calculating qty correctly
- [ ] WebSocket feed connected
- [ ] Redis tick cache populated

### Day 1 Checklist

- [ ] Review all trades executed
- [ ] Verify no duplicate orders
- [ ] Check PnL distribution reasonable
- [ ] Confirm cooldown logic working
- [ ] Validate exposure limits enforced
- [ ] Review metrics dashboard

### Week 1 Checklist

- [ ] Aggregate PnL positive (or within acceptable range)
- [ ] Win rate meets expectations
- [ ] No critical bugs or exceptions
- [ ] Performance metrics stable
- [ ] Team comfortable with monitoring

---

## Contact & Escalation

**On-Call Engineer:** [Your Contact]
**Trading System Lead:** [Your Contact]
**Emergency Hotline:** [Your Contact]

**Escalation Path:**
1. Check runbook troubleshooting section
2. Review logs and metrics
3. Contact on-call engineer
4. If critical (money at risk), escalate to lead immediately

---

## Appendix: Quick Reference Commands

### Check System Status
```bash
# Health check
curl http://localhost:3000/api/health

# Redis status
redis-cli ping

# WebSocket status (Rails console)
Live::MarketFeedHub.instance.running?
```

### View Recent Activity
```bash
# Last 50 signals
grep "\[Signal::Engines::" log/production.log | tail -50

# Last 20 orders
grep "\[Orders::Manager\]" log/production.log | tail -20

# Recent errors
grep -i "error\|exception" log/production.log | tail -30
```

### Manual Testing (Rails Console)
```ruby
# Test strategy engine
index_cfg = AlgoConfig.fetch[:indices].first
analyzer = Options::ChainAnalyzer.new(...)
candidate = analyzer.select_candidates(limit: 1).first
engine = Signal::Engines::MomentumBuyingEngine.new(...)
engine.evaluate
```

---

**Document Version:** 1.0
**Next Review:** After first production deployment

