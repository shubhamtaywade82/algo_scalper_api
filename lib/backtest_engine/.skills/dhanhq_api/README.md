# DhanHQ API

Comprehensive broker integration for market research, backtesting, paper trading, and live execution using DhanHQ APIs.

## Capabilities

- Authentication and session management
- Instrument discovery (Exchange, Segment, Security ID, Symbol, Lot Size, Tick Size, Expiry, Strike, Option Type)
- Market data (LTP, Quote, OHLC, Volume, OI, Bid, Ask, VWAP)
- Option chain (Expiry list, CE/PE, IV, OI, OI Change, Volume, Bid, Ask, Greeks, PCR)
- Historical data (1m to daily, OHLC + Volume + OI)
- Order management (Market, Limit, SL, SL-M, Modify, Cancel, Bracket, Forever Orders)
- Portfolio monitoring (Positions, Holdings, Funds, Margin, Trades)
- Live WebSocket feeds (Market feed, Order updates, Full depth)
- Derived calculations (ATR, VWAP, Intrinsic/Extrinsic Value, Premium Decay, Liquidity Score, Slippage Estimate)
- Intelligent caching (Instrument master, Expiry lists, Option chains, Historical candles, Security ID mappings)

## Recommended sub-skills

For better maintainability, split into focused modules:

- dhan_auth
- dhan_instruments
- dhan_market_data
- dhan_historical_data
- dhan_option_chain
- dhan_market_depth
- dhan_orders
- dhan_positions
- dhan_portfolio
- dhan_funds
- dhan_order_updates
- dhan_paper_trading
- dhan_execution_validation
- dhan_broker_health
