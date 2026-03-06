# Unnecessary Processes Running When Market is Closed

## Summary

When starting the app with `bin/dev` while the market is closed, several unnecessary processes are running that waste resources and make unnecessary API/database calls.

---

## Issues Found

### 1. ❌ AI Technical Analysis Job Running Every 5 Minutes

**Location**: `config/recurring.yml`

**Problem**:
- AI Technical Analysis jobs run every 5 minutes for both NIFTY and SENSEX
- Makes API calls to Ollama/OpenAI even when market is closed
- Fetches OHLC data, computes indicators, and generates analysis unnecessarily

**Evidence from Logs**:
```
[AgentRunner] Calling tool: compute_indicators with args: {:instrument_id=>104624, :timeframes=>["5m", "15m"]}
[OpenAIClient] Sending prompt to llama3.2:3b
[AgentRunner] Intent resolved: options_buying, symbol: NIFTY, confidence: 0.8
```

**Impact**:
- Unnecessary API calls to AI service
- Database queries for OHLC data
- CPU usage for indicator calculations
- Network traffic

**Fix**: Add market status check to job or disable in recurring.yml when market closed

---

### 2. ❌ RiskManagerService Running Expensive Queries

**Location**: `app/services/live/risk_manager_service.rb`

**Problem**:
- RiskManagerService runs every 5 seconds (`LOOP_INTERVAL = 5`)
- Calls `paper_trading_stats_with_pct` repeatedly which does expensive database queries
- No market closed check in `monitor_loop` method
- Even when no active positions, it still runs enforcement checks

**Evidence from Logs**:
```
↳ app/models/position_tracker.rb:100:in `paper_trading_stats_with_pct'
↳ app/models/position_tracker.rb:101:in `paper_trading_stats_with_pct'
↳ app/models/position_tracker.rb:103:in `paper_trading_stats_with_pct'
↳ app/models/position_tracker.rb:132:in `paper_trading_stats_with_pct'
↳ app/models/position_tracker.rb:215:in `paper_win_rate'
↳ app/services/live/risk_manager_service.rb:604:in `ensure_all_positions_in_redis'
↳ app/services/live/risk_manager_service.rb:391:in `enforce_hard_limits'
```

**Impact**:
- Expensive database queries every 5 seconds
- CPU usage for position tracking
- Memory usage for caching

**Current Behavior**:
- Service should check `TradingSession::Service.market_closed?` and sleep 60s if closed AND no active positions
- Currently missing this check in `monitor_loop`

**Fix**: Add market closed check similar to other services

---

### 3. ⚠️ Services Started When Market Closed

**Location**: `config/initializers/trading_supervisor.rb`

**Current Behavior**:
- When market is closed, supervisor should only start `MarketFeedHub`
- However, if services were already started before market closed, they continue running

**Expected Behavior** (from code):
```ruby
if market_closed
  Rails.logger.info('[TradingSupervisor] Market is closed - only starting WebSocket connection')
  supervisor[:market_feed]&.start
else
  supervisor.start_all
end
```

**Issue**:
- If app starts when market is open, then market closes, services continue running
- Services should check market status in their loops, but some don't

---

### 4. ✅ Services That DO Check Market Status (Good)

These services properly check market status and sleep when closed:

- **Signal::Scheduler**: ✅ Checks market closed, sleeps 30s
- **PaperPnlRefresher**: ✅ Checks market closed, sleeps 60s if no positions
- **PnlUpdaterService**: ✅ Checks market closed, sleeps 60s if no positions
- **ReconciliationService**: ✅ Checks market closed, sleeps 60s if no positions
- **StatsNotifierService**: ✅ Checks market closed, only sends stats once at close

---

## Recommended Fixes

### Fix 1: Add Market Check to AI Technical Analysis Job

**File**: `app/jobs/ai_technical_analysis_job.rb`

```ruby
def perform(index_name)
  # Skip if market is closed
  if TradingSession::Service.market_closed?
    Rails.logger.debug("[AiTechnicalAnalysisJob] Market closed - skipping analysis for #{index_name}")
    return
  end

  query = "OPTIONS buying intraday in INDEX like #{index_name}"
  # ... rest of code
end
```

**Alternative**: Disable in `config/recurring.yml` during non-trading hours (requires time-based scheduling)

---

### Fix 2: Add Market Check to RiskManagerService

**File**: `app/services/live/risk_manager_service.rb`

**Add to `monitor_loop` method** (around line 102):

```ruby
def monitor_loop(last_paper_pnl_update)
  # Skip processing if market is closed and no active positions
  if TradingSession::Service.market_closed?
    active_count = Positions::ActivePositionsCache.instance.active_trackers.size
    if active_count.zero?
      # Market closed and no active positions - sleep longer
      sleep 60 # Check every minute when market is closed and no positions
      return
    end
    # Market closed but positions exist - continue monitoring (needed for exits)
  end

  # Keep Redis/DB PnL fresh
  update_paper_positions_pnl_if_due(last_paper_pnl_update)
  # ... rest of code
end
```

---

### Fix 3: Stop Services When Market Closes

**File**: `config/initializers/trading_supervisor.rb`

**Option A**: Add periodic market status check to stop services when market closes

**Option B**: Rely on services to check market status themselves (current approach, but needs all services to implement it)

---

## Resource Usage Summary

### When Market is Closed (Current State)

| Process               | Frequency    | Impact                       | Status                |
| --------------------- | ------------ | ---------------------------- | --------------------- |
| AI Technical Analysis | Every 5 min  | High (API calls, DB queries) | ❌ Should skip         |
| RiskManagerService    | Every 5 sec  | High (DB queries, stats)     | ❌ Should check market |
| Signal::Scheduler     | Every 30 sec | Low (just checks market)     | ✅ Good                |
| PaperPnlRefresher     | Every 5 sec  | Low (checks market)          | ✅ Good                |
| PnlUpdaterService     | Every 60 sec | Low (checks market)          | ✅ Good                |
| ReconciliationService | Every 60 sec | Low (checks market)          | ✅ Good                |
| StatsNotifierService  | Every 60 sec | Low (checks market)          | ✅ Good                |
| MarketFeedHub         | Always       | Low (WebSocket only)         | ✅ Good                |

---

## Verification

After applying fixes, verify logs show:

```
[AiTechnicalAnalysisJob] Market closed - skipping analysis for NIFTY
[RiskManager] Market closed - no active positions, sleeping 60s
```

And no more:
- `[AgentRunner]` calls
- `[OpenAIClient]` API calls
- Repeated `paper_trading_stats_with_pct` queries

---

## Related Files

- `config/recurring.yml` - Recurring job configuration
- `app/jobs/ai_technical_analysis_job.rb` - AI analysis job
- `app/services/live/risk_manager_service.rb` - Risk manager service
- `config/initializers/trading_supervisor.rb` - Service supervisor
- `app/services/trading_session.rb` - Market status service
