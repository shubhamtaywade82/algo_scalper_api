# GO LIVE CHECKLIST + CAPITAL DEPLOYMENT PLAN

## PHASE 0 — HARD REQUIREMENTS (DO NOT SKIP)

- [ ] Backtest ≥ 60 trading days
- [ ] Expectancy > 0
- [ ] Max drawdown < 20%
- [ ] Win rate ≥ 35%
- [ ] At least 100 trades tested

---

## PHASE 1 — PAPER TRADING (1–2 WEEKS)

- [ ] Run full system live (no capital)
- [ ] Validate:
  - Order execution
  - Exit logic
  - No duplicate trades
- [ ] Compare with backtest

Exit condition:
- Live ≈ Backtest behavior

---

## PHASE 2 — ₹50,000 CAPITAL (SURVIVAL MODE)

### Rules

- Risk per trade: 0.5%
- Max daily loss: 2%
- Max trades/day: 3

### Objectives

- Survive (not profit)
- Validate execution reliability

### Kill Switch

- 3 consecutive losing days → STOP 2 days

---

## PHASE 3 — ₹1,00,000 CAPITAL

### Entry condition

- 2 profitable weeks
- Drawdown < 10%

### Rules

- Risk per trade: 1%
- Enable 2 strategies (diversification)

---

## PHASE 4 — ₹2,50,000 CAPITAL

### Entry condition

- Stable expectancy (>0.2)
- Max DD < 12%

### Rules

- Portfolio risk cap: 4%
- Enable full portfolio system

---

## PHASE 5 — ₹5,00,000 CAPITAL

### Entry condition

- 1 month consistency
- No system failures

### Rules

- Portfolio risk cap: 5%
- Dynamic sizing enabled

---

## LIVE SAFETY RULES

- Stop trading if:
  - Daily DD > 5%
  - 5 consecutive losses
  - API/order failures > 3

---

## DAILY ROUTINE

### Before Market
- Check system health
- Check capital + limits

### During Market
- Monitor execution logs
- Watch guardrail triggers

### After Market
- Run analytics
- Update rules (if needed)

---

## FINAL RULE

"Survive first. Scale later."
