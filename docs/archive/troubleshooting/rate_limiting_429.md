# Rate Limiting (429) Error Analysis

## Problem

The development logs show repeated `429: Unknown error` (rate limit) errors from `RiskManagerService.get_paper_ltp`:

```
[RiskManager] get_paper_ltp API error for TEST-1763808885-fe721b: DhanHQ::RateLimitError - 429: Unknown error
[RiskManager] get_paper_ltp API error for PAPER-NIFTY-35068-1763808135: DhanHQ::RateLimitError - 429: Unknown error
```

## Root Cause

1. **RiskManagerService runs every 5 seconds** (`LOOP_INTERVAL = 5`)
2. **`ensure_all_positions_in_redis` runs every 5 seconds** and calls `get_paper_ltp` for ALL active trackers
3. **`update_paper_positions_pnl` runs every 1 minute** and calls `get_paper_ltp` for ALL paper trackers
4. **No rate limiting between API calls** - `API_CALL_STAGGER_SECONDS = 1.0` is defined but **NOT USED**
5. **Direct API calls when cache is empty** - `get_paper_ltp` makes `DhanHQ::Models::MarketFeed.ltp` calls if TickCache is empty

## Impact

- Multiple API calls every 5 seconds for each active tracker
- No staggering/delay between calls
- DhanHQ API rate limit (likely ~10-20 requests/second) is exceeded
- 429 errors cause PnL updates to fail

## Solution

1. **Add rate limiting/staggering** between API calls using `API_CALL_STAGGER_SECONDS`
2. **Better cache utilization** - check `RedisTickCache` before API calls
3. **Batch API calls** - group multiple security_ids in single API call
4. **Exponential backoff** on 429 errors
5. **Reduce frequency** of `ensure_all_positions_in_redis` if cache is working

## Files to Fix

- `app/services/live/risk_manager_service.rb` - Add rate limiting in `get_paper_ltp` and `ensure_all_positions_in_redis`
- `app/services/live/risk_manager_service.rb` - Use `API_CALL_STAGGER_SECONDS` constant
- `app/services/live/risk_manager_service.rb` - Add exponential backoff on 429 errors

