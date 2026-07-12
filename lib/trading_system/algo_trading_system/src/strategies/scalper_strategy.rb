# frozen_string_literal: true

require_relative 'trading_strategies'

module TradingStrategies
  # Scalper Strategy using ATR and Range Expansion
  class ScalperStrategy < BaseStrategy
    attr_accessor :config

    def initialize(config = {})
      super(lookback_period: 20)
      @config = {
        'entry' => { 'range_expansion_threshold' => 1.5, 'atr_rising_lookback' => 3 },
        'strike_selection' => { 'delta_target' => 0.5 },
        'exit' => { 'mfe_ratio_nifty' => 0.4, 'initial_stop' => 0.15 },
        'risk' => { 'max_trades_per_day' => 3 }
      }.merge(config)
    end

    def signal
      return { action: 'HOLD' } if @history.length < 20

      # Simplified logic using parameters
      last_range = @history.last[:high] - @history.last[:low]
      avg_range = @history.last(10).map { |b| b[:high] - b[:low] }.sum / 10.0
      
      threshold = @config.dig('entry', 'range_expansion_threshold') || 1.5
      
      if last_range > (avg_range * threshold)
        { 
          action: 'BUY', 
          direction: 'LONG', 
          reason: "Range expansion (#{last_range.round(2)} > #{avg_range.round(2)} * #{threshold})" 
        }
      else
        { action: 'HOLD' }
      end
    end
  end
end
