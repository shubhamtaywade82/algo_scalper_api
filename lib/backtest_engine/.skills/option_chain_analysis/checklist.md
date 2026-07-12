# Option Chain Analysis Checklist

Use this checklist to ensure all quality gates are satisfied before taking trading decisions.

## 1. Expiry Selection Gate
- [ ] Retrieve available weekly and monthly expiry lists.
- [ ] Calculate days to expiry (DTE) for each contract.
- [ ] Measure baseline volume and open interest on near and next-week expiries.
- [ ] Map the implied volatility (IV) term structure slope.

## 2. Liquidity & Spread Gate
- [ ] Measure the absolute bid-ask spread and spread % `(Ask - Bid) / Bid * 100` for candidate strikes.
- [ ] Verify that the bid-ask spread is below `1.5%`.
- [ ] Check bid size and ask size depth at the top 5 levels of the book.
- [ ] Reject any strikes that have empty sizes or widen spreads.

## 3. OI & Volatility Gate
- [ ] Check current Open Interest (OI) and the change in OI over the last 15 minutes (OI velocity).
- [ ] Identify buildup category: Long Buildup, Short Buildup, Long Unwinding, or Short Covering.
- [ ] Scan for Call Wall (peak Call OI) and Put Wall (peak Put OI) locations.
- [ ] Compute Put-Call Ratio (PCR) and locate the Max Pain point.
- [ ] Calculate the IV skew and smile properties.

## 4. Greek Calculations
- [ ] Calculate option Delta, Gamma, Theta, and Vega.
- [ ] Estimate dealer positioning and Net Gamma Exposure (GEX) levels.
- [ ] Rank strikes using the multi-factor scoring formula.
