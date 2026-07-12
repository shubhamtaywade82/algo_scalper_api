# DHAN API VISUAL GUIDE & TESTING

## Quick API Test (CURL)
```bash
export DHAN_ACCESS_TOKEN="your_token"

curl --request POST \
  --url https://api.dhan.co/v2/charts/rollingoption \
  --header "access-token: $DHAN_ACCESS_TOKEN" \
  --header "content-type: application/json" \
  --data '{
    "exchangeSegment": "NSE_FNO",
    "interval": "5",
    "securityId": 13,
    "instrument": "OPTIDX",
    "expiryFlag": "WEEK",
    "expiryCode": 0,
    "strike": "ATM",
    "drvOptionType": "CALL",
    "requiredData": ["open","high","low","close","iv","spot"],
    "fromDate": "2024-01-01",
    "toDate": "2024-01-05"
  }'
```

## Data Field Descriptions
- **IV (Implied Volatility)**: Annualized percentage.
- **Spot**: The value of the underlying index at the time of the option bar.
- **Security IDs**: 
  - Nifty 50: `13`
  - BankNifty: `12`
  - FinNifty: `27`
  - Sensex: `1`

## Strike Selection Logic
- `ATM`: At-the-money.
- `ATM+n`: Next OTM strikes (e.g., `ATM+1`, `ATM+2`).
- `ATM-n`: Next ITM strikes (e.g., `ATM-1`, `ATM-2`).
- Supports up to `ATM±10` for Index near expiry.

## Data Flow Diagram
```
[DhanHQ Servers] 
      ↓ (Encrypted JSON)
[DhanApiClient] 
      ↓ (Normalizes to Candle Objects)
[OptionsEngine FSM] ← [Strategy Signals]
      ↓ (Executes Trades)
[Net P&L Reports]
```
