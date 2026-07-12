# DhanHQ API Reference for Market Structure Analysis

Use these endpoints and inputs when pulling candle streams to construct structural maps.

## 1. Spot Index Candles

### Intraday Candle Retrieval
* **Endpoint**: `POST /charts/intraday`
* **Purpose**: Retrieves candle history (timestamp, open, high, low, close, volume) for indicators.
* **Payload**:
  ```json
  {
    "securityId": "13",
    "exchangeSegment": "NSE_IDX",
    "instrument": "INDEX",
    "interval": "5",
    "fromDateTime": "2026-07-09 09:15:00",
    "toDateTime": "2026-07-09 15:30:00"
  }
  ```

---

## 2. Option Chain support levels

### Option Chain Boundaries
* **Endpoint**: `POST /optionchain`
* **Purpose**: Retrieves call/put walls to map OI-based support and resistance levels.
* **Payload**:
  ```json
  {
    "underlyingSecurityId": 13,
    "underlyingExchangeSegment": "NSE_IDX",
    "expiryDate": "2026-07-16"
  }
  ```
