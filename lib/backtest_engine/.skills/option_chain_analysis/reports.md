# Option Chain Analysis Reports Specification

This skill generates both detailed markdown reports for human review and structured JSON files for system consumption.

## Generated Reports

1. **`option_chain_summary.md`**: Top-level dashboard detailing ATM strike, market bias, maximum pain, and primary walls.
2. **`expiry_analysis.md`**: Term structure comparison of weekly vs. monthly option premiums, and volume/OI allocations.
3. **`strike_scores.md`**: Leaderboard table of Call and Put strikes sorted by the multi-factor scoring formula.
4. **`opportunity_report.md`**: Structural alerts highlighting volatility contractions, gamma triggers, or potential breakout targets.
5. **`risk_report.md`**: Alerts for wide spreads, low depth liquidity, or imminent IV crush events.

## Report Update Frequency
* **Backtesting**: Generated at the end of the simulation run as an audit log.
* **Paper / Live Trading**: Updated continuously every 5 minutes during the trading session and cached in `data/knowledge_base/`.
