# DhanHQ API Reference for Option Chain Analysis

Use these endpoints to load real-time option chains and historical contract records.

## 1. Expiry Discovery

### Fetch Expiries
* **Endpoint**: `POST /optionchain/expirylist`
* **Purpose**: Resolves active expiry dates for the selected underlying index.
* **Payload**:
  ```json
  {
    "underlyingSecurityId": 13,
    "underlyingExchangeSegment": "NSE_IDX"
  }
  ```

---

## 2. Option Chain Profiles

### Fetch Option Chain
* **Endpoint**: `POST /optionchain`
* **Purpose**: Retrieves quotes, Open Interest, Implied Volatility, and volume columns.
* **Payload**:
  ```json
  {
    "underlyingSecurityId": 13,
    "underlyingExchangeSegment": "NSE_IDX",
    "expiryDate": "2026-07-16"
  }
  ```

---

## 3. Historical Options Data

### Rolling Options History
* **Endpoint**: `POST /charts/rollingoption`
* **Purpose**: Pulls expired option contracts' minute-level OHLC, volume, and OI.
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
    "requiredData": ["close", "volume", "oi", "iv"],
    "fromDate": "2026-06-01",
    "toDate": "2026-07-01"
  }
  ```
