# 📡 TickerChannel Usage Guide

The `TickerChannel` is an ActionCable WebSocket channel that provides real-time market data streaming to web clients. It's already integrated into the home page and ready to use.

## 🏗️ Architecture Overview

```
DhanHQ WebSocket → Live::MarketFeedHub → TickerChannel → Web Browser
```

### **Data Flow:**
1. **DhanHQ WebSocket** receives live market data
2. **Live::MarketFeedHub** processes and broadcasts ticks
3. **TickerChannel** streams data to connected clients
4. **Web Browser** receives real-time updates via ActionCable

## 🚀 Current Implementation

### **TickerChannel Class**
```ruby
# app/channels/ticker_channel.rb
class TickerChannel < ApplicationCable::Channel
  CHANNEL_ID = :market_feed

  def subscribed
    stream_for CHANNEL_ID
    Rails.logger.info("TickerChannel subscription established")
  end

  def unsubscribed
    stop_all_streams
  end
end
```

### **Broadcasting from MarketFeedHub**
```ruby
# app/services/live/market_feed_hub.rb
def handle_tick(tick)
  Live::TickCache.put(tick)
  ActiveSupport::Notifications.instrument("dhanhq.tick", tick)

  # Broadcast to Action Cable subscribers
  if defined?(::TickerChannel)
    ::TickerChannel.broadcast_to(::TickerChannel::CHANNEL_ID, tick)
  end

  @callbacks.each { |callback| safe_invoke(callback, tick) }
end
```

## 🌐 Web Client Integration

### **Current Home Page Implementation**
The home page (`/`) already includes a complete TickerChannel implementation:

- **URL**: `http://localhost:3000/`
- **Features**:
  - Real-time display of NIFTY, BANKNIFTY, and SENSEX
  - Connection status indicator
  - Responsive design with modern styling
  - Console logging for debugging

### **JavaScript Client Code**
```javascript
// Stimulus Controller for Ticker Display
class TickerDisplayController {
  static targets = ["ltp", "timestamp"];
  static values = { segment: String, securityId: String };

  connect() {
    this.setupSubscription();
  }

  setupSubscription() {
    if (!window.tickerCable) {
      window.tickerCable = consumer.createConsumer("/cable");
      window.tickerSubscription = window.tickerCable.subscriptions.create(
        { channel: "TickerChannel" },
        {
          received: (data) => this.handleTick(data),
          connected: () => this.updateConnectionStatus('connected'),
          disconnected: () => this.updateConnectionStatus('disconnected')
        }
      );
    }
  }

  handleTick(data) {
    const key = `${data.segment}:${data.security_id}`;
    const expected = `${this.segmentValue}:${this.securityIdValue}`;

    if (key === expected && data.ltp) {
      this.ltpTarget.textContent = Number(data.ltp).toFixed(2);
      this.timestampTarget.textContent = new Date().toLocaleTimeString();
    }
  }
}
```

## 📊 Data Format

### **Tick Data Structure**
```ruby
{
  segment: "IDX_I",           # Exchange segment (IDX_I, NSE_FNO, BSE_FNO)
  security_id: "13",         # Security ID (13=NIFTY, 25=BANKNIFTY, 51=SENSEX)
  ltp: 25285.50,            # Last Traded Price
  kind: :quote,             # Data type (:quote, :trade, etc.)
  ts: 1760128146,           # Timestamp
  atp: 0.0,                 # Average Trade Price
  vol: 0,                   # Volume
  day_open: 25167.65,       # Day's opening price
  day_high: 25330.75,       # Day's high
  day_low: 25156.85,        # Day's low
  day_close: 25285.35       # Day's closing price
}
```

## 🔧 Configuration

### **ActionCable Setup**
```ruby
# config/routes.rb
mount ActionCable.server => "/cable"

# config/cable.yml
development:
  adapter: solid_cable
```

### **Environment Variables**
```bash
# Required for DhanHQ WebSocket
DHANHQ_CLIENT_ID=your_client_id
DHANHQ_ACCESS_TOKEN=your_access_token
DHANHQ_WS_ENABLED=true
```

## 🧪 Testing the TickerChannel

### **Manual Testing**
```bash
# Start the server
bin/rails server -p 3000

# Open browser
open http://localhost:3000/

# Test broadcast from console
bin/rails runner "
TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, {
  segment: 'IDX_I',
  security_id: '13',
  ltp: 25000.50,
  kind: :quote
})
"
```

### **Automated Testing**
```ruby
# spec/channels/ticker_channel_spec.rb
RSpec.describe TickerChannel, type: :channel do
  it "subscribes to the channel" do
    subscribe
    expect(subscription).to be_confirmed
  end

  it "receives broadcasted ticks" do
    subscribe
    tick_data = { segment: "IDX_I", security_id: "13", ltp: 25000.50 }

    expect {
      TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, tick_data)
    }.to have_broadcasted_to(TickerChannel::CHANNEL_ID).with(tick_data)
  end
end
```

## 🎯 Usage Examples

### **1. Add New Instrument Display**
```html
<div class="ticker-card"
     data-controller="ticker-display"
     data-ticker-display-segment-value="NSE_FNO"
     data-ticker-display-security-id-value="12345">
  <h3>📈 RELIANCE</h3>
  <div class="ltp" data-ticker-display-target="ltp">Loading...</div>
  <div class="timestamp" data-ticker-display-target="timestamp">-</div>
</div>
```

### **2. Custom Tick Handler**
```javascript
class CustomTickerController extends TickerDisplayController {
  handleTick(data) {
    super.handleTick(data);

    // Custom logic
    if (data.ltp > this.previousLtp) {
      this.ltpTarget.style.color = 'green';
    } else if (data.ltp < this.previousLtp) {
      this.ltpTarget.style.color = 'red';
    }
    this.previousLtp = data.ltp;
  }
}
```

### **3. Multiple Subscriptions**
```javascript
// Subscribe to multiple instruments
const instruments = [
  { segment: 'IDX_I', security_id: '13' },  // NIFTY
  { segment: 'IDX_I', security_id: '25' },  // BANKNIFTY
  { segment: 'NSE_FNO', security_id: '12345' } // RELIANCE
];

instruments.forEach(instrument => {
  // Create individual controllers for each instrument
  const controller = new TickerDisplayController();
  controller.segmentValue = instrument.segment;
  controller.securityIdValue = instrument.security_id;
});
```

## 🚨 Troubleshooting

### **Common Issues**

#### **1. No Data Received**
- Check WebSocket connection status in browser console
- Verify DhanHQ credentials are configured
- Ensure MarketFeedHub is running

#### **2. Connection Failed**
- Check ActionCable server is mounted at `/cable`
- Verify Redis is running (for SolidCable)
- Check browser console for WebSocket errors

#### **3. Data Not Updating**
- Verify security_id matches exactly
- Check segment format (IDX_I, NSE_FNO, BSE_FNO)
- Ensure MarketFeedHub is subscribed to the instrument

### **Debug Commands**
```bash
# Check WebSocket subscriptions
bin/rails runner "puts Live::MarketFeedHub.instance.watchlist"

# Test broadcast manually
bin/rails runner "TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, {test: 'data'})"

# Check ActionCable status
curl -v http://localhost:3000/cable
```

## 📈 Performance Considerations

### **Optimization Tips**
1. **Single Subscription**: Use one WebSocket connection per page
2. **Efficient Filtering**: Filter ticks on the client side
3. **Debouncing**: Limit update frequency for UI elements
4. **Memory Management**: Clean up subscriptions on page unload

### **Scaling**
- ActionCable supports multiple concurrent connections
- SolidCable provides database-backed message queuing
- Consider Redis for production scaling

## 🔗 Related Files

- **Channel**: `app/channels/ticker_channel.rb`
- **Controller**: `app/controllers/home_controller.rb`
- **Service**: `app/services/live/market_feed_hub.rb`
- **Routes**: `config/routes.rb`
- **Cable Config**: `config/cable.yml`

## 🎉 Ready to Use!

The TickerChannel is fully functional and integrated. Simply:

1. **Start the server**: `bin/rails server`
2. **Open browser**: `http://localhost:3000/`
3. **See live data**: NIFTY, BANKNIFTY, and SENSEX updates in real-time

The implementation is production-ready with proper error handling, connection management, and responsive design! 🚀
