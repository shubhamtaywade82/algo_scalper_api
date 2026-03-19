# frozen_string_literal: true

module Positions
  class RiskCandidates
    def self.call(max_loss:)
      threshold = -max_loss.to_f.abs
      PositionTracker.active.where('COALESCE(last_pnl_rupees, 0) <= ?', threshold)
    end
  end
end
