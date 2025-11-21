# 🔧 TickerChannel Troubleshooting Guide

## 🚨 Issue: WebSocket Not Connecting / Data Not Loading

If you're seeing "Connection Status: Connecting..." and the tickers show "Loading..." without updates, follow this troubleshooting guide.

## 🔍 Step-by-Step Debugging

### **1. Check Server Status**
```bash
# Verify Rails server is running
ps aux | grep "rails server"

# Check server logs
tail -f log/development.log
```

### **2. Test Basic Connectivity**
```bash
# Test if server responds
curl http://localhost:3000/

# Test ActionCable endpoint
curl -v http://localhost:3000/cable
```

### **3. Use Debug Page**
Open the debug page in your browser:
```
http://localhost:3000/debug.html
```

This page will:
- ✅ Show detailed WebSocket connection logs
- ✅ Test connection automatically
- ✅ Display real-time ticker updates
- ✅ Provide manual test buttons

### **4. Check Browser Console**
1. Open `http://localhost:3000/` in your browser
2. Press `F12` to open Developer Tools
3. Go to **Console** tab
4. Look for error messages or connection logs

**Expected logs:**
```
Script loading...
TickerDisplay connected for IDX_I:13
Setting up subscription...
Creating ActionCable consumer...
Creating subscription...
WebSocket connected!
```

### **5. Test Manual Broadcast**
```bash
# Test broadcast from terminal
cd /home/nemesis/project/algo_scalper_api
bin/rails runner "
TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, {
  segment: 'IDX_I',
  security_id: '13',
  ltp: 25000.50,
  kind: :quote
})
"
```

### **6. Test API Endpoint**
```bash
# Test via API
curl -X POST http://localhost:3000/api/test_broadcast \
  -H "Content-Type: application/json" \
  -d '{"segment":"IDX_I","security_id":"13","ltp":25000.50}'
```

## 🛠️ Common Issues & Solutions

### **Issue 1: "Connection Status: Connecting..." Forever**

**Possible Causes:**
- ActionCable not properly configured
- WebSocket connection blocked by firewall
- JavaScript errors preventing connection

**Solutions:**
1. **Check ActionCable config:**
   ```ruby
   # config/cable.yml should have:
   development:
     adapter: async
   ```

2. **Check routes:**
   ```ruby
   # config/routes.rb should have:
   mount ActionCable.server => "/cable"
   ```

3. **Restart server:**
   ```bash
   pkill -f "rails server"
   bin/rails server -p 3000
   ```

### **Issue 2: "WebSocket connection rejected"**

**Possible Causes:**
- CSRF token issues
- Authentication problems
- CORS issues

**Solutions:**
1. **Check CSRF protection:**
   ```ruby
   # config/environments/development.rb
   config.action_cable.disable_request_forgery_protection = true
   ```

2. **Check allowed origins:**
   ```ruby
   # config/environments/development.rb
   config.action_cable.allowed_request_origins = [/http:\/\/localhost.*/]
   ```

### **Issue 3: Data Received But Not Displayed**

**Possible Causes:**
- JavaScript filtering issues
- Target element not found
- Data format mismatch

**Solutions:**
1. **Check browser console for errors**
2. **Verify data format:**
   ```javascript
   // Expected format:
   {
     segment: "IDX_I",
     security_id: "13",
     ltp: 25000.50,
     kind: "quote"
   }
   ```

3. **Check element targeting:**
   ```html
   <!-- Make sure these elements exist -->
   <span data-ticker-display-target="ltp">Loading...</span>
   <span data-ticker-display-target="timestamp">-</span>
   ```

### **Issue 4: Server Errors**

**Check server logs for:**
- Database connection issues
- Missing environment variables
- DhanHQ WebSocket problems

**Solutions:**
1. **Check environment variables:**
   ```bash
   echo $CLIENT_ID
   echo $DHANHQ_ACCESS_TOKEN
   ```

2. **Run health check:**
   ```bash
   bin/health_check
   ```

## 🧪 Testing Commands

### **Quick Tests**
```bash
# 1. Test server response
curl http://localhost:3000/

# 2. Test ActionCable
curl -v http://localhost:3000/cable

# 3. Test broadcast
bin/rails runner "TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, {test: 'data'})"

# 4. Test API endpoint
curl -X POST http://localhost:3000/api/test_broadcast
```

### **Browser Tests**
1. **Main page:** `http://localhost:3000/`
2. **Debug page:** `http://localhost:3000/debug.html`
3. **Health API:** `http://localhost:3000/api/health`

## 📊 Expected Behavior

### **Working Connection:**
- ✅ Connection Status shows "Connected"
- ✅ Tickers display real LTP values
- ✅ Timestamps update
- ✅ Browser console shows connection logs
- ✅ Debug page shows received data

### **Not Working:**
- ❌ Connection Status shows "Connecting..." forever
- ❌ Tickers show "Loading..."
- ❌ No console logs
- ❌ Debug page shows connection errors

## 🚀 Quick Fixes

### **Restart Everything:**
```bash
# Kill existing server
pkill -f "rails server"

# Clear any locks
rm -f tmp/pids/server.pid

# Restart server
bin/rails server -p 3000
```

### **Clear Browser Cache:**
1. Press `Ctrl+Shift+R` (hard refresh)
2. Or open in incognito/private mode

### **Check Network:**
1. Disable browser extensions
2. Try different browser
3. Check firewall settings

## 📞 Still Not Working?

If none of the above solutions work:

1. **Check the debug page:** `http://localhost:3000/debug.html`
2. **Share the browser console logs**
3. **Share the server logs**
4. **Try the API endpoint:** `http://localhost:3000/api/test_broadcast`

The debug page will show exactly what's happening with the WebSocket connection and help identify the specific issue.
