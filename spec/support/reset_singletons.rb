# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    # Reset known singletons that hold state
    [
      Live::MarketFeedHub,
      Live::RedisPnlCache,
      Live::RedisTickCache,
      Live::PositionIndex,
      Positions::ActiveCache,
      Live::TickCache,
      Live::WsHub
    ].each do |singleton_class|
      if defined?(singleton_class) && singleton_class.respond_to?(:instance)
        begin
          instance = singleton_class.instance
          
          # Manually clear instance variables to ensure no mocks leak
          # We keep @lock if it exists to avoid threading issues
          instance.instance_variables.each do |ivar|
            next if ivar == :@lock || ivar == :@mutex
            
            # Reset to original state or nil
            if ivar == :@running
              instance.instance_variable_set(ivar, false)
            elsif ivar == :@subscribed_keys || ivar == :@callbacks
              instance.instance_variable_set(ivar, Concurrent::Array.new)
            elsif ivar == :@watchlist_keys
              instance.instance_variable_set(ivar, Concurrent::Set.new)
            else
              instance.instance_variable_set(ivar, nil)
            end
          end
        rescue StandardError => e
          Rails.logger.debug("Failed to reset singleton #{singleton_class}: #{e.message}")
        end
      end
    end
  end
end
