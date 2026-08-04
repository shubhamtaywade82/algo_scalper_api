# frozen_string_literal: true

class SignalEngine
  STRATEGIES = [].freeze

  INDICES = %i[nifty banknifty sensex].freeze

  def initialize(indices: INDICES)
    @indices = indices
    @signals = []
  end

  def run
    Rails.logger.info('[SignalEngine] Alpha strategies disabled — use Strategies::Manager path')
    []
  end
end
