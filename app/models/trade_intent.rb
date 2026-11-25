# frozen_string_literal: true

# A Rails entry signal handed to options-trading-agent for execution (contract trade-intent/1).
# The agent pulls pending intents and reports one outcome per intent (intent-outcome/1).
class TradeIntent < ApplicationRecord
  MODES = %w[paper sandbox live].freeze
  DIRECTIONS = %w[BULLISH BEARISH].freeze
  OUTCOMES = %w[accepted dropped expired duplicate].freeze

  belongs_to :strategy_signal, class_name: 'Strategies::Signal', optional: true

  validates :intent_id, presence: true, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :underlying, :source_strategy, :expires_at, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :pending, ->(now = Time.current) { where(outcome: nil).where('expires_at > ?', now) }

  def decided?
    outcome.present?
  end

  # Contract view of whether the agent ever answered; unanswered intents past expiry show as such in the UI.
  def display_outcome(now = Time.current)
    return outcome if decided?

    expires_at <= now ? 'unanswered' : 'pending'
  end
end
