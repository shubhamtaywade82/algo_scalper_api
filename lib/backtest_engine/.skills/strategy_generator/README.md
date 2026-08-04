# Strategy Generator

Institutional Strategy Research Engine that discovers, designs, validates, evolves, and retires trading strategies based on quantitative evidence. Acts as an AI Quant Researcher, not an LLM that invents strategies randomly.

## Pipeline

Every strategy follows this evidence pipeline:

1. **Market Research** — Identify market conditions and opportunities
2. **Hypothesis** — Define a testable market hypothesis
3. **Feature Selection** — Choose indicators and data features
4. **Signal Design** — Create entry and exit signals
5. **Risk Design** — Define stop loss, take profit, trailing, position sizing
6. **Trade Management** — Define filters, strike selection, option selection
7. **Backtest** — Run historical backtest
8. **Walk Forward** — Validate out-of-sample performance
9. **Monte Carlo** — Stress test robustness
10. **Paper Trading** — Forward test in simulated environment
11. **Performance Analysis** — Evaluate all metrics
12. **Ranking** — Compare against existing strategies
13. **Deployment** — Promote to paper or live

## Key Principles

- Every strategy begins with a market hypothesis
- Never skip validation
- Never recommend a strategy purely because of profit
- Robustness always ranks above returns
- Inferior mutations are rejected
- Strategies can be retired based on evidence
