# Strategy Engine Rollout Checklist

**Deployment Date:** _______________
**Deployed By:** _______________
**Environment:** [ ] Staging [ ] Production
**Strategy:** [ ] Momentum Buying [ ] Open Interest [ ] BTST [ ] Swing [ ] All

---

## Pre-Deployment (Day Before)

### Code & Tests
- [ ] All PRs merged to target branch
- [ ] CI pipeline green (tests, lint, security)
- [ ] Backtest run completed and report reviewed
- [ ] Code review approved by 2+ engineers
- [ ] No open critical bugs

### Configuration
- [ ] `config/algo.yml` validated (YAML syntax correct)
- [ ] Strategy configs reviewed:
  - [ ] `active` strategy set correctly
  - [ ] `direction` set (bullish/bearish)
  - [ ] All `lot_multiplier` values are integers >= 1
  - [ ] `capital_alloc_pct` values between 0.0 and 1.0
- [ ] Paper trading enabled (`paper_trading.enabled: true`)
- [ ] Config changes documented in CHANGELOG

### Infrastructure
- [ ] Redis accessible and healthy
- [ ] Database migrations applied (if any)
- [ ] WebSocket feed tested and running
- [ ] DhanHQ API credentials valid
- [ ] Option chain API accessible

### Observability
- [ ] Log aggregation configured
- [ ] Metrics dashboard accessible
- [ ] Alerting rules configured
- [ ] Team has access to monitoring tools

### Communication
- [ ] Deployment window scheduled
- [ ] Team notified of deployment
- [ ] On-call engineer aware
- [ ] Rollback plan communicated

---

## Deployment Day - Pre-Deploy (30 minutes before)

### Final Checks
- [ ] Current system status healthy (no active alerts)
- [ ] No critical positions at risk
- [ ] Backup of current config created
- [ ] Rollback commit identified
- [ ] Deployment branch checked out

### Environment Prep
- [ ] Staging environment matches production config
- [ ] Test strategy engine in staging first (if applicable)
- [ ] Verify paper trading balance set correctly

---

## Deployment - Step by Step

### Step 1: Deploy Code (5 minutes)

- [ ] Code deployed to target environment
- [ ] Worker container/service restarted
- [ ] Verify no startup errors in logs:
  ```bash
  tail -f log/production.log | grep -i "error\|exception" | head -20
  ```

### Step 2: Verify Startup (5 minutes)

- [ ] TradingSupervisor started (check logs)
- [ ] SignalScheduler running (check logs)
- [ ] WebSocket feed connected
- [ ] Health endpoint returns 200:
  ```bash
  curl http://localhost:3000/api/health
  ```

### Step 3: Enable Strategy (2 minutes)

- [ ] Update `config/algo.yml` with target strategy:
  ```yaml
  strategy:
    active: "momentum_buying"  # or target strategy
  ```
- [ ] Config reloaded (or worker restarted if needed)
- [ ] Verify strategy active in logs:
  ```bash
  grep "\[SignalScheduler\]" log/production.log | tail -5
  ```

### Step 4: Initial Monitoring (15 minutes)

- [ ] Watch logs for signal generation:
  ```bash
  tail -f log/production.log | grep -E "Signal|EntryGuard|Orders"
  ```
- [ ] Verify signals being generated (expect 0-5 in first 15 min)
- [ ] Check EntryGuard processing signals
- [ ] Verify no exceptions or errors

### Step 5: Validate First Trade (10 minutes)

- [ ] Wait for first signal (if conditions met)
- [ ] Verify EntryGuard passed
- [ ] Check Allocator calculated qty > 0
- [ ] Confirm order placed (paper mode):
  ```ruby
  # Rails console
  PositionTracker.paper.order(created_at: :desc).first
  ```
- [ ] Verify order details correct (qty, price, symbol)

---

## Post-Deployment - Hour 1

### Immediate Validation
- [ ] No exceptions in logs
- [ ] Signals generated (count > 0 or expected 0 if conditions not met)
- [ ] EntryGuard processing (check pass/reject ratio)
- [ ] Orders placed successfully (if signals passed)
- [ ] WebSocket feed stable
- [ ] Redis tick cache populated

### Metrics Check
- [ ] Signal generation rate reasonable
- [ ] EntryGuard rejection rate acceptable
- [ ] Allocator qty calculations look correct
- [ ] No DhanHQ API errors (429, 500, timeout)
- [ ] System latency within normal range

### Log Review
- [ ] Review last 100 log lines for errors
- [ ] Check for any unexpected warnings
- [ ] Verify strategy engine logs present

---

## Post-Deployment - Day 1

### Morning Check (9:00 AM)
- [ ] Review overnight activity (signals, trades)
- [ ] Check PnL for paper positions
- [ ] Verify no duplicate orders
- [ ] Confirm cooldown logic working
- [ ] Review exposure limits enforced

### Midday Check (1:00 PM)
- [ ] Review morning trading activity
- [ ] Check for any anomalies
- [ ] Verify strategy conditions being met correctly
- [ ] Review allocator decisions

### End of Day (4:00 PM)
- [ ] Aggregate daily stats:
  - [ ] Total signals generated
  - [ ] Total trades executed
  - [ ] Win rate
  - [ ] Average PnL per trade
- [ ] Review any issues encountered
- [ ] Document any config adjustments needed

---

## Post-Deployment - Week 1

### Daily Checks (Repeat each day)
- [ ] Review previous day's trades
- [ ] Check PnL distribution
- [ ] Verify no critical bugs
- [ ] Monitor system performance
- [ ] Review team feedback

### Weekly Summary (End of Week 1)
- [ ] Aggregate weekly stats:
  - [ ] Total signals: _______
  - [ ] Total trades: _______
  - [ ] Win rate: _______%
  - [ ] Total PnL: ₹_______
  - [ ] Max drawdown: ₹_______
- [ ] Review strategy performance vs expectations
- [ ] Identify any config optimizations needed
- [ ] Document lessons learned

---

## Canary Deployment Checklist (If Applicable)

### Phase 1: Minimal Capital (48-72 hours)
- [ ] Strategy enabled with `capital_alloc_pct: 0.01` (1%)
- [ ] `lot_multiplier: 1` (minimum)
- [ ] Monitor for 48 hours
- [ ] Review all trades
- [ ] Verify no issues
- [ ] **Decision:** [ ] Proceed to Phase 2 [ ] Rollback [ ] Adjust config

### Phase 2: Increase Capital (24-48 hours)
- [ ] Increase to `capital_alloc_pct: 0.02` (2%)
- [ ] Monitor for 24 hours
- [ ] Review trades
- [ ] **Decision:** [ ] Proceed to Phase 3 [ ] Rollback [ ] Adjust config

### Phase 3: Add Second Strategy (48-72 hours)
- [ ] Enable second strategy
- [ ] Monitor for 48 hours
- [ ] Review both strategies independently
- [ ] **Decision:** [ ] Proceed to Full Rollout [ ] Rollback [ ] Adjust config

---

## Rollback Checklist (If Needed)

### Immediate Rollback (< 5 minutes)
- [ ] Set `DISABLE_TRADING_SUPERVISOR=true` in environment
- [ ] Restart worker container/service
- [ ] Verify supervisor stopped (check logs)
- [ ] Confirm no new orders being placed

### Config Rollback (If Config Issue)
- [ ] Revert `config/algo.yml` to previous version
- [ ] Restart worker if needed
- [ ] Verify old behavior restored

### Code Rollback (If Code Bug)
- [ ] Identify rollback commit
- [ ] Revert code to previous version
- [ ] Redeploy previous version
- [ ] Verify system stable

### Post-Rollback
- [ ] Document reason for rollback
- [ ] Review what went wrong
- [ ] Create bug ticket if needed
- [ ] Schedule retry deployment (if applicable)

---

## Go-Live Checklist (Production Only)

### Pre-Go-Live (1 week before)
- [ ] Staging validation complete (7+ days)
- [ ] Backtest results reviewed and acceptable
- [ ] Team trained on runbook
- [ ] On-call rotation scheduled
- [ ] Monitoring dashboards ready

### Go-Live Day
- [ ] All pre-deployment checks complete
- [ ] Deploy to production
- [ ] Enable with minimal capital (1-2%)
- [ ] Monitor closely for first 4 hours
- [ ] Review first trades carefully

### Post-Go-Live (First Week)
- [ ] Daily review of all trades
- [ ] Monitor for any issues
- [ ] Gradually increase capital (if successful)
- [ ] Document any adjustments

---

## Sign-Off

**Deployment Completed By:** _______________
**Date:** _______________
**Time:** _______________

**Validated By:** _______________
**Date:** _______________

**Notes:**
```
[Space for deployment notes, issues encountered, config changes, etc.]
```

---

## Emergency Contacts

**On-Call Engineer:** _______________
**Phone:** _______________

**Trading System Lead:** _______________
**Phone:** _______________

**DevOps/Infrastructure:** _______________
**Phone:** _______________

---

**Checklist Version:** 1.0
**Last Updated:** 2025-01-XX

