# Troubleshooting & Operational Guide

Common issues and remediation steps for the trading system.

## 1. Connectivity Issues

### WebSocket Not Connecting
- **Symptom**: "MarketFeedHub not running" in logs or 0 ticks on the dashboard.
- **Fix**: Check `DHAN_ACCESS_TOKEN` validity. Tokens usually expire every 24-48 hours. Use the `DhanHQ::Client` log to identify `401 Unauthorized` errors.

### Missing Ticks for Specific Options
- **Symptom**: Signal engine identifies a strike, but no price updates follow.
- **Fix**: Ensure the `security_id` for the option strike is correctly resolved. Check `Options::ChainAnalyzer` logs for strike lookup failures.

## 2. Order Execution Failures

### Insufficient Funds
- **Symptom**: `400 Bad Request` or `Insufficient Margin` reported in `PositionTracker.meta`.
- **Fix**: Check broker balance. Ensure `Entries::EntryGuard` exposure settings align with your available margin.

### Bracket Orders Rejected
- **Symptom**: Orders rejected with "RMS:Rule: Equity limit exceeded".
- **Fix**: Verify if your broker account supports Bracket Orders for the selected segment. Switch to Market/Limit orders in `config/algo.yml`.

## 3. Data Integrity

### Redis Sync Issues
- **Symptom**: PnL on dashboard doesn't match the actual PnL reported by `UnifiedExitChecker`.
- **Fix**: Flush Redis or restart the trading daemon. The loop in `RiskManagerService` will re-sync PnL on the next tick.

### Ghost Positions
- **Symptom**: A position is marked `active` in the DB but is closed at the broker.
- **Fix**: Run the reconciliation task:
  ```bash
  bundle exec rake trading:reconcile
  ```

## 4. Critical Halt (Circuit Breaker)

If the system stops taking trades, check the circuit breaker status:
```bash
# Via Rails Console
Risk::CircuitBreaker.instance.status

# To Reset
Risk::CircuitBreaker.instance.reset!
```
