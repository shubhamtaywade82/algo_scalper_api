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
      next unless defined?(singleton_class) && singleton_class.respond_to?(:instance)

      begin
        instance = singleton_class.instance

        # Smart reset based on class
        if singleton_class == Live::PositionIndex
          instance.clear if instance.respond_to?(:clear)
          instance.instance_variable_set(:@index, Concurrent::Map.new) if instance.instance_variable_get(:@index).nil?
        elsif singleton_class == Live::TickCache
          instance.clear if instance.respond_to?(:clear)
        elsif singleton_class == Positions::ActiveCache
          instance.clear if instance.respond_to?(:clear)
        elsif singleton_class == Live::MarketFeedHub
          instance.stop! if instance.respond_to?(:running?) && instance.running?
          # Force clear even if stop! didn't (e.g. if it was already stopped but had state)
          instance.instance_variable_set(:@subscribed_keys, Concurrent::Set.new)
          instance.instance_variable_set(:@watchlist_keys, Concurrent::Set.new)
          instance.instance_variable_set(:@callbacks, Concurrent::Array.new)
          instance.instance_variable_set(:@ws_client, nil)
        else
          # Generic fallback for other singletons
          instance.instance_variables.each do |ivar|
            next if [:@lock, :@mutex, :@index].include?(ivar)

            val = instance.instance_variable_get(ivar)
            if val.is_a?(Concurrent::Map)
              val.clear
            elsif val.is_a?(Concurrent::Array) || val.is_a?(Array)
              val.clear
            elsif val.is_a?(Concurrent::Set) || val.is_a?(Set)
              val.clear
            elsif ivar == :@running
              instance.instance_variable_set(ivar, false)
            else
              # Only set to nil if not a fundamental state container
              # We explicitly include @redis here to prevent mock leakage
              instance.instance_variable_set(ivar, nil) unless [:@index, :@cache, :@queue].include?(ivar) && ivar != :@redis
            end
          end
        end
      rescue StandardError => e
        Rails.logger.debug("Failed to reset singleton #{singleton_class}: #{e.message}")
      end
    end
  end
end
