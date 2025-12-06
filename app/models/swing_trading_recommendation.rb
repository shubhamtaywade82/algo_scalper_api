# frozen_string_literal: true

# == Schema Information
#
# Table name: swing_trading_recommendations
#
#  id                  :integer          not null, primary key
#  watchlist_item_id   :integer          not null
#  symbol_name         :string           not null
#  segment             :string           not null
#  security_id         :string           not null
#  recommendation_type :string           not null
#  direction           :string           not null
#  entry_price         :decimal(12, 4)   not null
#  stop_loss           :decimal(12, 4)   not null
#  take_profit         :decimal(12, 4)   not null
#  quantity            :integer          not null
#  allocation_pct     :decimal(5, 2)   not null
#  hold_duration_days  :integer          not null
#  confidence_score   :decimal(5, 4)
#  status              :string           default("active")
#  technical_analysis  :jsonb            default({})
#  volume_analysis     :jsonb            default({})
#  reasoning           :text
#  analysis_timestamp  :datetime         not null
#  expires_at          :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

class SwingTradingRecommendation < ApplicationRecord
  belongs_to :watchlist_item

  enum :recommendation_type, {
    swing: 'swing',
    long_term: 'long_term'
  }

  enum :direction, {
    buy: 'buy',
    sell: 'sell'
  }

  enum :status, {
    active: 'active',
    executed: 'executed',
    expired: 'expired',
    cancelled: 'cancelled'
  }

  validates :symbol_name, presence: true
  validates :segment, presence: true
  validates :security_id, presence: true
  validates :entry_price, presence: true, numericality: { greater_than: 0 }
  validates :stop_loss, presence: true, numericality: { greater_than: 0 }
  validates :take_profit, presence: true, numericality: { greater_than: 0 }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :allocation_pct, presence: true, numericality: { in: 0.0..100.0 }
  validates :hold_duration_days, presence: true, numericality: { greater_than: 0 }
  validates :confidence_score, numericality: { in: 0.0..1.0 }, allow_nil: true
  validates :analysis_timestamp, presence: true

  scope :active, -> { where(status: :active) }
  scope :for_symbol, ->(symbol) { where(symbol_name: symbol) }
  scope :by_type, ->(type) { where(recommendation_type: type) }
  scope :recent, ->(hours = 24) { where(analysis_timestamp: hours.hours.ago..Time.current) }
  scope :high_confidence, ->(threshold = 0.7) { where(confidence_score: threshold..) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }

  # Calculate risk-reward ratio
  def risk_reward_ratio
    return nil if entry_price.to_f.zero?

    risk = (entry_price.to_f - stop_loss.to_f).abs
    reward = (take_profit.to_f - entry_price.to_f).abs

    return nil if risk.zero?

    (reward / risk).round(2)
  end

  # Calculate total investment amount
  def investment_amount
    (entry_price.to_f * quantity).round(2)
  end

  # Check if recommendation is still valid
  def valid?
    active? && (expires_at.nil? || expires_at > Time.current)
  end

  # Get technical analysis summary
  def technical_summary
    return {} if technical_analysis.blank?

    {
      supertrend: technical_analysis['supertrend'],
      adx: technical_analysis['adx'],
      rsi: technical_analysis['rsi'],
      macd: technical_analysis['macd'],
      trend: technical_analysis['trend']
    }
  end

  # Get volume analysis summary
  def volume_summary
    return {} if volume_analysis.blank?

    {
      avg_volume: volume_analysis['avg_volume'],
      current_volume: volume_analysis['current_volume'],
      volume_ratio: volume_analysis['volume_ratio'],
      volume_trend: volume_analysis['trend']
    }
  end
end
