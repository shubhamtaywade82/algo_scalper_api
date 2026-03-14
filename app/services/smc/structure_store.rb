# frozen_string_literal: true

module Smc
  # Persists the deterministic state of structural levels (BOS, FVGs, OBs) to Redis
  class StructureStore
    def initialize(symbol, interval)
      @symbol = symbol
      @interval = interval
      @redis = Redis.new # Assuming a standard Redis connection
    end

    def update_state(data)
      key = "smc:state:#{@symbol}:#{@interval}"
      @redis.set(key, data.to_json)
    end

    def get_state
      key = "smc:state:#{@symbol}:#{@interval}"
      raw = @redis.get(key)
      raw ? JSON.parse(raw, symbolize_names: true) : default_state
    end

    private

    def default_state
      {
        trend: :neutral,
        last_bos: nil,
        last_choch: nil,
        active_fvgs: [],
        active_obs: []
      }
    end
  end
end
