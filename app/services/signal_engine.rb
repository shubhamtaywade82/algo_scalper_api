# frozen_string_literal: true

class SignalEngine
  STRATEGIES = [
    MomentumAlpha,
    VolExpansionAlpha,
    EventAlpha,
    GammaScalpAlpha,
    ExpiryAlpha
  ].freeze

  INDICES = %i[nifty banknifty sensex].freeze

  def initialize(indices: INDICES)
    @indices = indices
    @signals = []
  end

  def run
    @indices.each do |index_key|
      STRATEGIES.each do |strategy_class|
        next if strategy_disabled?(strategy_class, index_key)

        begin
          strategy = strategy_class.new(index_key: index_key)
          signal = strategy.scan

          next unless signal.present? && signal_valid?(signal)

          signal = score_signal(signal)
          @signals << signal if signal[:confidence] > 0.55
        rescue StandardError => e
          Rails.logger.error "[SignalEngine] Strategy #{strategy_class} failed for #{index_key}: #{e.message}"
        end
      end
    end

    # Group by index and take the highest confidence signal per index
    @signals.group_by { |s| s[:index_key] }.transform_values do |sigs|
      sigs.max_by { |s| s[:confidence] }
    end.values
  end

  private

  def strategy_disabled?(klass, index_key)
    config = AlgoConfig.fetch[:alpha_strategies] || {}
    index_config = config[index_key.to_s] || config[index_key] || {}
    strategy_key = klass.name.demodulize.underscore
    index_config[strategy_key] == false
  end

  def signal_valid?(signal)
    signal[:entry_price] > 0 &&
      signal[:stop_loss] > 0 &&
      signal[:target] > 0 &&
      signal[:confidence] > 0.5 &&
      signal[:expiry].present?
  end

  def score_signal(signal)
    win_prob = signal[:confidence].to_f
    loss_prob = 1.0 - win_prob
    risk = (signal[:entry_price] - signal[:stop_loss]).abs
    reward = (signal[:target] - signal[:entry_price]).abs

    # Expected Value (EV) = (Win Prob * Reward) - (Loss Prob * Risk)
    ev = (win_prob * reward) - (loss_prob * risk)
    signal[:expected_value] = ev.round(2)

    # Confidence boost for positive EV
    if ev > 0
      signal[:confidence] = [(signal[:confidence] + 0.03), 0.95].min
    end

    signal
  end
end
