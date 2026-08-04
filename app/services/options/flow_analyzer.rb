# frozen_string_literal: true

module Options
  # Real-time option chain flow analysis for institutional liquidity detection
  class FlowAnalyzer
    attr_reader :chain_data, :index_key, :expiry_date

    def initialize(index_key:, expiry_date:, chain_data:)
      @index_key = index_key.to_s.upcase
      @expiry_date = expiry_date
      @chain_data = chain_data # { last_price: float, oc: { strike => { ce: {}, pe: {} } } }
    end

    # Identifies strikes with strong institutional flow (long buildup)
    # @return [Hash] { 'ce' => [strikes], 'pe' => [strikes] }
    def strong_flow_strikes
      result = { 'ce' => [], 'pe' => [] }
      return result unless @chain_data && @chain_data[:oc]

      @chain_data[:oc].each do |strike, data|
        %w[ce pe].each do |type|
          option = data[type]
          next unless option && option['oi'].to_i.positive?

          score = calculate_flow_score(strike, type, option)
          if score > 1.2
            result[type] << { strike: strike.to_f, score: score, data: option }
          end
        end
      end

      # Sort by score descending
      result['ce'].sort_by! { |s| -s[:score] }
      result['pe'].sort_by! { |s| -s[:score] }

      result
    end

    # Returns historical data for a specific strike
    # @return [Hash, nil]
    def get_history(strike, type)
      get_strike_history(strike, type)
    end

    private

    def calculate_flow_score(strike, type, option)
      # Get historical context from cache
      history = get_strike_history(strike, type)
      
      # Default scores if no history
      return 1.0 if history.blank?

      prev_oi = history[:oi].to_f
      prev_price = history[:ltp].to_f
      avg_volume = history[:avg_volume].to_f

      current_oi = option['oi'].to_f
      current_price = option['last_price'].to_f
      current_volume = option['volume'].to_f

      # 1. OI Change (50% weight)
      oi_change_pct = prev_oi.positive? ? (current_oi - prev_oi) / prev_oi : 0.0
      
      # 2. Volume Spike (30% weight)
      vol_ratio = avg_volume.positive? ? current_volume / avg_volume : 1.0
      
      # 3. Price Change (20% weight)
      price_change_pct = prev_price.positive? ? (current_price - prev_price) / prev_price : 0.0

      # Flow score formula
      score = (oi_change_pct * 0.5) + (vol_ratio * 0.3) + (price_change_pct * 0.2)

      # Record current state for next cycle
      record_strike_state(strike, type, option)

      score
    end

    def cache_key(strike, type)
      "flow_history:#{@index_key}:#{@expiry_date}:#{strike}:#{type}"
    end

    def get_strike_history(strike, type)
      Rails.cache.read(cache_key(strike, type))
    end

    def record_strike_state(strike, type, option)
      current_state = {
        oi: option['oi'],
        ltp: option['last_price'],
        volume: option['volume'],
        timestamp: Time.current
      }

      # Update rolling averages (simple 5-period for responsiveness)
      history = get_strike_history(strike, type) || {}
      
      prev_volumes = history[:volume_history] || []
      prev_volumes << option['volume'].to_f
      prev_volumes = prev_volumes.last(5)
      
      prev_ois = history[:oi_history] || []
      prev_ois << option['oi'].to_f
      prev_ois = prev_ois.last(5)
      
      current_state[:volume_history] = prev_volumes
      current_state[:avg_volume] = prev_volumes.sum / prev_volumes.size.to_f
      
      current_state[:oi_history] = prev_ois
      current_state[:avg_oi] = prev_ois.sum / prev_ois.size.to_f

      Rails.cache.write(cache_key(strike, type), current_state, expires_in: 1.hour)
    end
  end
end
