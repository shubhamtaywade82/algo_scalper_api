# Risk Management

Institutional-grade risk engine for long-only index options. Acts as the Chief Risk Officer — every strategy, backtest, paper trade, and live trade must pass through this gate.

## Capabilities

- Position sizing (Fixed, Kelly, ATR, Volatility Adjusted, Optimal F, Risk Parity, etc.)
- Capital management (Available, Blocked, Allocated, Risk Budget, Cash Reserve)
- Trade risk evaluation (Entry/Stop/Target, R Multiple, Max Loss, Risk Score)
- Portfolio risk (Heat, VaR, CVaR, Expected Shortfall, Concentration, Correlation)
- Exposure monitoring (Underlying, Direction, Expiry, Strike, Greeks)
- Correlation management across NIFTY, BANKNIFTY, FINNIFTY, MIDCPNIFTY, SENSEX, BANKEX
- Volatility monitoring (HV, RV, IV, IV Rank/Percentile, ATR, Regime)
- Drawdown tracking and recovery management
- Circuit breakers (Loss limits, Consecutive losses, System health)
- Stress testing (Spread, Liquidity, IV Crush, Theta, Gap, Broker/Exchange failure)
- Risk models (Fixed Fractional, Kelly, CPPI, VaR/CVaR, Risk Parity, Monte Carlo, Bayesian, Regime Adaptive)

## Decisions

- APPROVE
- APPROVE_WITH_WARNING
- REDUCE_SIZE
- REJECT
- EMERGENCY_EXIT

## Institutional Extensions for Options

- Greek Risk Engine (Delta, Gamma, Theta, Vega, Rho limits)
- Expiry Risk Engine (tighten risk as expiry approaches)
- Premium Risk Engine (IV Rank, Percentile, Premium-to-ATR)
- Execution Risk Engine (Bid-ask spread, Depth, Slippage)
- Regime-Adaptive Risk Engine
- Strategy Kill Switch
