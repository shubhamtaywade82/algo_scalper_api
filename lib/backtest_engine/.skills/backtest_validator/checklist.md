# Backtest Validation Quality Checklist

Every backtest must be audited against this checklist before it can be marked as production-ready.

## 1. Data Integrity Check
- [ ] Scan index candles for gaps (empty minutes).
- [ ] Verify timezone offsets and market sessions are aligned.
- [ ] Confirm expiry calendar is correct (includes holiday shifts).
- [ ] Audit historical options chain files for pricing consistency.

## 2. Leakage & Bias Check
- [ ] Verify that indicator calculations do not access future index prices.
- [ ] Check that option selection does not use future option chains.
- [ ] Ensure entry triggers do not execute on the same candle that generated the signal.
- [ ] Verify no survivorship bias is present in the underlying index database.

## 3. Cost & Brokerage Check
- [ ] Enforce brokerage charge per trade.
- [ ] Deduct GST, exchange fees, SEBI charges, and stamp duties.
- [ ] Apply Securities Transaction Tax (STT) on buy and sell premium.
- [ ] Apply slippage penalty (default: 0.5% - 2.0% based on contract spreads).

## 4. Robustness Audits
- [ ] Run Walk-Forward Analysis (WFA) and verify Walk-Forward Efficiency $\text{WFE} \ge 0.6$.
- [ ] Run 10,000 Monte Carlo runs by reordering trades. Verify maximum drawdown risk boundaries.
- [ ] Run random entry benchmark and verify strategy outperformance ($p\text{-value} < 0.05$).
