# DhanHQ API Reference for Indicator Research

Use these endpoints to pull candles and chain metrics for indicator validation.

## 1. Index Candlesticks

### Intraday Candles
* **Endpoint**: `POST /charts/intraday`
* **Purpose**: Fetches minute-level candles to compute lag and smoothing characteristics.
* **Payload**:
  ```json
  {
    "securityId": "13",
    "exchangeSegment": "NSE_IDX",
    "instrument": "INDEX",
    "interval": "1",
    "fromDateTime": "2026-07-09 09:15:00",
    "toDateTime": "2026-07-09 15:30:00"
  }
  ```

---

## 2. Options History

### Expired Option Candles
* **Endpoint**: `POST /charts/rollingoption`
* **Purpose**: Retrieves historical minute-level option data (OHLC, IV, OI) to test premium features.
* **Payload**:
  ```json
  {
    "securityId": 13,
    "exchangeSegment": "NSE_FNO",
    "instrument": "OPTIDX",
    "expiryFlag": "WEEK",
    "expiryCode": 0,
    "strike": "ATM",
    "drvOptionType": "CALL",
    "requiredData": ["open", "high", "low", "close", "volume", "oi", "iv"],
    "fromDate": "2026-06-01",
    "toDate": "2026-07-01"
  }
  ```
