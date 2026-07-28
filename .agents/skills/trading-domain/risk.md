# Risk Engine Design & Rules

## Risk Engine Architecture

1. **Pre-trade evaluation**: Evaluated BEFORE order submission. NEVER after.
2. **Rule Composability**: Rules are independent, orderable POROs.
3. **Auditability**: Every rejected signal is logged with the specific rule name and reason.
4. **Configuration-Driven**: Thresholds are loaded from YAML, not hardcoded.
5. **Circuit Breakers**: Global kill switch halts ALL trading instantly.

---

## Pre-Trade Risk Rules List

- **`MaxPositionSize`**: Per-instrument lot limit.
- **`MaxDailyLoss`**: Stop trading if daily PnL $\le -X$ paise.
- **`MarginAvailability`**: Required margin $\le$ available account margin.
- **`MaxOrdersPerMinute`**: Rate limit order submissions.
- **`MaxOpenOrders`**: Total pending orders cap.
- **`InstrumentAllowed`**: Security ID whitelist check.
- **`MarketHours`**: Session time validity check.
- **`CircuitBreaker`**: Global kill switch state check.

---

## Configuration Schema (`config/risk_limits.yml`)

```yaml
default:
  max_position_lots: 10
  max_daily_loss_paise: -500000
  max_orders_per_minute: 5
  max_open_orders: 20
  margin_buffer_percent: 15

circuit_breaker:
  max_daily_loss_paise: -1000000
  max_drawdown_percent: 5
  cooldown_minutes: 30

instruments:
  NIFTY_FUT:
    max_position_lots: 5
  BANKNIFTY_FUT:
    max_position_lots: 3
```
