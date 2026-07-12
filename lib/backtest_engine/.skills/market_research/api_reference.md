# DhanHQ API Reference for Market Research

Use these endpoints and payload patterns when retrieving market data for analysis.

## 1. Instrument Discovery

### Segment Instruments
* **Endpoint**: `GET /instruments/{exchangeSegment}`
* **Purpose**: Fetches active option symbols, strikes, lot sizes, and security IDs.
* **Payload Examples**:
  ```text
  Segment: NSE_FNO
  Result: NIFTY 24200 CE, lot size 75, securityId 14231
  ```

---

## 2. Historical & Intraday Data

### Intraday Candles
* **Endpoint**: `POST /charts/intraday`
* **Purpose**: Extracts minute-level candles for indicator computation.
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

## 3. Options Chain

### Expiry List
* **Endpoint**: `POST /optionchain/expirylist`
* **Purpose**: Identifies tradable expiry contracts.

### Option Chain Details
* **Endpoint**: `POST /optionchain`
* **Purpose**: Retrieves volume, open interest, and implied volatility.
* **Payload**:
  ```json
  {
    "underlyingSecurityId": 13,
    "underlyingExchangeSegment": "NSE_IDX",
    "expiryDate": "2026-07-16"
  }
  ```
