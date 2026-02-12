# frozen_string_literal: true

# Helper to disable WebSocket connections during RSpec tests
# Uses minimal stubbing - only prevents actual WebSocket client creation
# Allows rest of code to execute normally so method calls can be verified

RSpec.configure do |config|
  # Disable WebSocket connections globally for all tests
  config.before(:suite) do
    # Ensure WebSocket is disabled via environment variables
    ENV['DHANHQ_WS_ENABLED'] = 'false'
    ENV['DHANHQ_ORDER_WS_ENABLED'] = 'false'
    ENV['DISABLE_TRADING_SERVICES'] = '1'

    # Remove credentials to prevent WebSocket initialization
    # (MarketFeedHub.enabled? checks for credentials)
    ENV.delete('DHAN_CLIENT_ID')
    ENV.delete('CLIENT_ID')
    ENV.delete('DHAN_ACCESS_TOKEN')
    ENV.delete('ACCESS_TOKEN')
  end

  # Minimal stubbing: Only prevent actual WebSocket client creation
  # Let the rest of the code execute normally so we can verify method calls
  config.before(:each) do
    if defined?(Live::MarketFeedHub)
      # Create a mock WebSocket client that can track method calls
      mock_ws_client = instance_double('DhanHQ::WS::Client',
                                       start: true,
                                       stop: true,
                                       disconnect!: true,
                                       connected?: false,
                                       on: true,
                                       subscribe_one: true,
                                       subscribe_many: true,
                                       unsubscribe_one: true)

      # Only stub build_client to prevent actual WebSocket client creation
      # This is the minimal stub needed - everything else should execute normally
      allow_any_instance_of(Live::MarketFeedHub).to receive(:build_client).and_return(mock_ws_client)

      # Stub ensure_running! to not raise, but allow it to execute logic
      # This allows subscribe calls to work while still allowing verification
      allow_any_instance_of(Live::MarketFeedHub).to receive(:ensure_running!).and_wrap_original do |method, *args|
        hub = method.receiver
        # If hub is not enabled, start! won't work, so we need to mock running? temporarily
        # This allows the code path to execute without raising
        if hub.respond_to?(:enabled?) && !hub.enabled? && !hub.running?
          allow(hub).to receive(:running?).and_return(true)
        end
        # Call original to verify it's being called
        begin
          method.call(*args)
        rescue RuntimeError => e
          # If it raises "not running", allow it to pass (we've mocked running? to true)
          raise e unless e.message.include?('not running')
        end
      end
    end
  end
end

# Usage in tests to verify WebSocket method calls:
#   hub = Live::MarketFeedHub.instance
#   expect(hub).to receive(:subscribe).with(segment: 'NSE_FNO', security_id: '12345')
#   # The minimal stubs above don't interfere with expect() calls
