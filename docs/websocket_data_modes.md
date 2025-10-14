# WebSocket Data Modes Guide

This guide explains how to switch between mock data and live WebSocket data for the Algo Scalper API homepage.

## **Current Status: ✅ LIVE WEBSOCKET DATA ENABLED**

The server is now running with live DhanHQ WebSocket data enabled.

---

## **Data Modes Overview**

### **1. Mock Data Mode**
- **Purpose**: Development and testing when live data is unavailable
- **Data Source**: `Live::MockDataService` generates random LTP values
- **Frequency**: Updates every 2 seconds
- **Environment**: `DHANHQ_WS_ENABLED=false`

### **2. Live WebSocket Mode**
- **Purpose**: Production trading with real market data
- **Data Source**: DhanHQ WebSocket API
- **Frequency**: Real-time market ticks
- **Environment**: `DHANHQ_WS_ENABLED=true` (default)

---

## **How to Switch Between Modes**

### **Switch to Mock Data Mode**

```bash
# Stop current server
kill -9 $(cat tmp/pids/server.pid) 2>/dev/null || true

# Start with mock data
DHANHQ_WS_ENABLED=false DHANHQ_ORDER_WS_ENABLED=false bin/rails server -p 3000
```

**Expected Logs:**
```
[MockData] Starting mock data service (WebSocket disabled)
[MockData] Broadcasted NIFTY: 25291
[MockData] Broadcasted BANKNIFTY: 56598
[MockData] Broadcasted SENSEX: 82224
```

### **Switch to Live WebSocket Mode**

```bash
# Stop current server
kill -9 $(cat tmp/pids/server.pid) 2>/dev/null || true

# Start with live data (default)
bin/rails server -p 3000
```

**Expected Logs:**
```
[WS tick] IDX_I:13 ltp=25145.5 kind=quote
[WS tick] IDX_I:25 ltp=56496.44921875 kind=quote
[WS tick] IDX_I:51 ltp=82343.59 kind=quote
```

---

## **Verification Steps**

### **1. Check Data Source in Logs**

**Mock Data:**
```bash
tail -f log/development.log | grep "MockData"
```

**Live Data:**
```bash
tail -f log/development.log | grep "WS tick"
```

### **2. Test Homepage**

Visit `http://localhost:3000/` and verify:
- ✅ Connection Status shows "Connected"
- ✅ All three tickers display LTP values
- ✅ Values update in real-time
- ✅ Timestamps update with each tick

### **3. Manual Test Broadcast**

Test the API endpoint:
```bash
curl -s http://localhost:3000/api/test_broadcast -X POST -d "segment=IDX_I&security_id=13&ltp=25250.50"
```

---

## **Troubleshooting**

### **Mock Data Not Starting**
- Check environment variable: `echo $DHANHQ_WS_ENABLED`
- Verify initializer: `config/initializers/mock_data_service.rb`
- Check logs for: `[MockData] Starting mock data service`

### **Live WebSocket Not Connecting**
- Check DhanHQ credentials in `config/credentials.yml.enc`
- Verify WebSocket configuration in `config/algo.yml`
- Check for rate limiting errors (HTTP 429)
- Look for WebSocket connection logs

### **Homepage Not Updating**
- Check browser console for JavaScript errors
- Verify ActionCable connection: `Started GET "/cable"`
- Check TickerChannel subscription: `TickerChannel subscription established`
- Test manual broadcast API

---

## **Configuration Files**

### **Mock Data Service**
- **File**: `app/services/live/mock_data_service.rb`
- **Initializer**: `config/initializers/mock_data_service.rb`
- **Trigger**: `ENV["DHANHQ_WS_ENABLED"] == "false"`

### **Live WebSocket Service**
- **File**: `app/services/live/market_feed_hub.rb`
- **Configuration**: `config/algo.yml`
- **Credentials**: `config/credentials.yml.enc`

---

## **Performance Notes**

### **Mock Data Mode**
- ✅ No API rate limits
- ✅ Consistent update frequency
- ✅ Reliable for development
- ❌ Not real market data

### **Live WebSocket Mode**
- ✅ Real market data
- ✅ Production-ready
- ❌ Subject to API rate limits
- ❌ May have connection issues

---

## **Current Status**

**✅ LIVE WEBSOCKET DATA ENABLED**

The server is running with live DhanHQ WebSocket data. You should see:
- Real market LTP values for NIFTY, BANKNIFTY, and SENSEX
- Live updates as market ticks arrive
- Connection status showing "Connected"

To switch back to mock data, use the commands above with `DHANHQ_WS_ENABLED=false`.
