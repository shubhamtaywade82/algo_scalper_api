# DHAN API MAPPING (Production Trading)

This document maps the DhanHQ API specifications to the system implementation.

## 1. Intraday Historical Data
`POST https://api.dhan.co/v2/charts/intraday`

**Usage**: Used for pre-loading candle data to warm up indicators in live trading.

### Request
```json
{
  "securityId": "13",
  "exchangeSegment": "NSE_FNO",
  "instrument": "INDEX",
  "interval": "1",
  "oi": true,
  "fromDate": "2024-09-11 09:15:00",
  "toDate": "2024-09-12 15:30:00"
}
```

### Response
```json
{
  "open": [3750, ...],
  "high": [3750, ...],
  "low": [3750, ...],
  "close": [3750, ...],
  "volume": [166, ...],
  "timestamp": [1328845020, ...],
  "open_interest": [0, ...]
}
```

## 2. Daily Historical Data
`POST https://api.dhan.co/v2/charts/historical`

**Usage**: Used for long-term trend analysis and daily-level backtesting.

## 3. Expired Options Data
`POST https://api.dhan.co/v2/charts/rollingoption`

**Usage**: Core endpoint for backtesting historical option strategies.

### Request
```json
{
  "securityId": "13",
  "exchangeSegment": "NSE_FNO",
  "instrument": "OPTIDX",
  "expiryFlag": "WEEK",
  "expiryCode": 1,
  "strike": "ATM", // or ATM+1, ATM-1 etc.
  "drvOptionType": "CALL",
  "requiredData": ["open", "high", "low", "close", "iv", "volume", "strike", "oi", "spot"],
  "fromDate": "2024-09-01",
  "toDate": "2024-09-05"
}
```

### Response Mapping
- System maps `CALL` → `ce` and `PUT` → `pe` in the response data object.
- `expiryCode`: `0` for current expiry, `1` for next expiry (mandatory).
- `strike`: Offset based (e.g. `ATM`, `ATM+1`, `ATM-1`).
- `requiredData`: Must include `iv`, `volume`, `strike`, `oi`, `spot` for full strategy support.


## 4. Live Market Data (WebSocket)
`wss://api-feed.dhan.co`

**Usage**: Real-time LTP (Last Traded Price) updates during live trading sessions.
- System subscribes to Index/Option ticks.
- `CandleAggregator` builds live candles from these ticks.
