# frozen_string_literal: true

# Strategy Recommender Service
# Provides recommendations for best strategy/timeframe combinations based on backtest results
class StrategyRecommender
  # Backtest results data (should be updated after each comprehensive backtest)
  BACKTEST_RESULTS = {
    'NIFTY' => {
      '5' => {
        strategy: SimpleMomentumStrategy,
        strategy_name: 'SimpleMomentumStrategy',
        win_rate: 52.63,
        expectancy: 0.02,
        total_pnl: 0.98,
        trades: 57
      },
      '15' => {
        strategy: SupertrendAdxStrategy,
        strategy_name: 'SupertrendAdxStrategy',
        win_rate: 42.86,
        expectancy: -0.35,
        total_pnl: -2.47,
        trades: 7
      }
    },
    'BANKNIFTY' => {
      '5' => {
        strategy: SimpleMomentumStrategy,
        strategy_name: 'SimpleMomentumStrategy',
        win_rate: 55.77,
        expectancy: 0.04,
        total_pnl: 2.22,
        trades: 52
      },
      '15' => {
        strategy: InsideBarStrategy,
        strategy_name: 'InsideBarStrategy',
        win_rate: 57.14,
        expectancy: -0.27,
        total_pnl: -1.89,
        trades: 7
      }
    },
    'SENSEX' => {
      '5' => {
        strategy: SupertrendAdxStrategy,
        strategy_name: 'SupertrendAdxStrategy',
        win_rate: 52.54,
        expectancy: 0.03,
        total_pnl: 1.62,
        trades: 59
      },
      '15' => {
        strategy: SimpleMomentumStrategy,
        strategy_name: 'SimpleMomentumStrategy',
        win_rate: 71.43,
        expectancy: 0.18,
        total_pnl: 1.23,
        trades: 7
      }
    }
  }.freeze

  class << self
    # Get recommended strategy for a given index and timeframe
    # @param symbol [String] Index symbol (NIFTY, BANKNIFTY, SENSEX)
    # @param interval [String] Timeframe in minutes ('5', '15')
    # @return [Hash] Strategy recommendation with details
    def recommend(symbol:, interval: '5')
      symbol = symbol.to_s.upcase
      interval = interval.to_s

      result = BACKTEST_RESULTS.dig(symbol, interval)
      return default_recommendation(symbol, interval) unless result

      {
        symbol: symbol,
        interval: interval,
        strategy_class: result[:strategy],
        strategy_name: result[:strategy_name],
        win_rate: result[:win_rate],
        expectancy: result[:expectancy],
        total_pnl: result[:total_pnl],
        trades: result[:trades],
        recommended: result[:expectancy].positive?,
        confidence: calculate_confidence(result)
      }
    end

    # Get best strategy across all timeframes for an index
    # @param symbol [String] Index symbol
    # @return [Hash] Best strategy recommendation
    def best_for_index(symbol:)
      symbol = symbol.to_s.upcase
      results = BACKTEST_RESULTS[symbol] || {}

      return nil if results.empty?

      # Find best by expectancy
      best = results.max_by { |_interval, data| data[:expectancy] || -999 }
      return nil unless best

      interval, data = best
      {
        symbol: symbol,
        interval: interval,
        strategy_class: data[:strategy],
        strategy_name: data[:strategy_name],
        win_rate: data[:win_rate],
        expectancy: data[:expectancy],
        total_pnl: data[:total_pnl],
        trades: data[:trades],
        recommended: data[:expectancy].positive?,
        confidence: calculate_confidence(data)
      }
    end

    # Get all recommendations for an index
    # @param symbol [String] Index symbol
    # @return [Array<Hash>] All strategy recommendations sorted by expectancy
    def all_for_index(symbol:)
      symbol = symbol.to_s.upcase
      results = BACKTEST_RESULTS[symbol] || {}

      recommendations = results.map do |interval, data|
        {
          symbol: symbol,
          interval: interval,
          strategy_class: data[:strategy],
          strategy_name: data[:strategy_name],
          win_rate: data[:win_rate],
          expectancy: data[:expectancy],
          total_pnl: data[:total_pnl],
          trades: data[:trades],
          recommended: data[:expectancy].positive?,
          confidence: calculate_confidence(data)
        }
      end
      recommendations.sort_by { |r| -(r[:expectancy] || -999) }
    end

    # Get recommended configuration for live trading
    # @return [Hash] Recommended configuration for all indices
    def live_trading_config
      {
        'NIFTY' => recommend(symbol: 'NIFTY', interval: '5'),
        'BANKNIFTY' => recommend(symbol: 'BANKNIFTY', interval: '5'),
        'SENSEX' => recommend(symbol: 'SENSEX', interval: '5')
      }
    end

    private

    def default_recommendation(symbol, interval)
      {
        symbol: symbol,
        interval: interval,
        strategy_class: SimpleMomentumStrategy,
        strategy_name: 'SimpleMomentumStrategy',
        win_rate: nil,
        expectancy: nil,
        total_pnl: nil,
        trades: nil,
        recommended: false,
        confidence: :low,
        note: 'No backtest data available - using default strategy'
      }
    end

    def calculate_confidence(data)
      return :low if data[:trades] < 20
      return :low if data[:expectancy].negative?

      if data[:expectancy] > 0.03 && data[:trades] > 50
        :high
      elsif data[:expectancy].positive? && data[:trades] > 30
        :medium
      else
        :low
      end
    end
  end
end
