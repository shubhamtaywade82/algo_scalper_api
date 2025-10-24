# frozen_string_literal: true

class TradingSignal < ApplicationRecord
  DIRECTIONS = {
    bullish: "bullish",
    bearish: "bearish",
    avoid: "avoid"
  }.freeze

  validates :index_key, presence: true
  validates :direction, inclusion: { in: DIRECTIONS.values }
  validates :timeframe, presence: true
  validates :signal_timestamp, presence: true
  validates :candle_timestamp, presence: true
  validates :confidence_score, numericality: { in: 0.0..1.0 }, allow_nil: true

  scope :for_index, ->(index_key) { where(index_key: index_key) }
  scope :for_direction, ->(direction) { where(direction: direction) }
  scope :recent, ->(hours = 24) { where(signal_timestamp: hours.hours.ago..Time.current) }
  scope :high_confidence, ->(threshold = 0.7) { where("confidence_score >= ?", threshold) }

  def self.create_from_analysis(index_key:, direction:, timeframe:, supertrend_value:, adx_value:, candle_timestamp:, confidence_score: nil, metadata: {})
    create!(
      index_key: index_key,
      direction: direction,
      timeframe: timeframe,
      supertrend_value: supertrend_value,
      adx_value: adx_value,
      candle_timestamp: candle_timestamp,
      signal_timestamp: Time.current,
      confidence_score: confidence_score,
      metadata: metadata
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to persist trading signal: #{e.record.errors.full_messages.to_sentence}")
    nil
  end

  def confidence_level
    return "unknown" unless confidence_score

    case confidence_score
    when 0.8..1.0 then "very_high"
    when 0.6..0.8 then "high"
    when 0.4..0.6 then "medium"
    when 0.2..0.4 then "low"
    else "very_low"
    end
  end

  def bullish?
    direction == DIRECTIONS[:bullish]
  end

  def bearish?
    direction == DIRECTIONS[:bearish]
  end

  def avoid?
    direction == DIRECTIONS[:avoid]
  end
end
