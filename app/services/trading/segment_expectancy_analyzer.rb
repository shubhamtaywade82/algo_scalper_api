# frozen_string_literal: true

require 'singleton'

module Trading
  # SegmentExpectancyAnalyzer — realized win-rate/expectancy by (index, session-regime) segment
  #
  # PROBLEM: The bot's exits and sizing are now session-aware (Live::TimeRegimeService —
  # S1 Open Expansion / S2 Trend Continuation / S3 Chop-Theta / S4 Close-Gamma), but ENTRY
  # decisions still treat every segment as equally tradeable. If, say, BANKNIFTY entries
  # during S3 (the chop/theta "danger zone") have been a realized net-negative-expectancy
  # segment over the last two weeks, nothing currently throttles new entries into that
  # exact pattern — the bot keeps re-fighting a fight it's statistically been losing.
  #
  # This service computes realized expectancy (avg PnL per trade) and win-rate per
  # (index_key, regime) segment from closed PositionTracker rows over a rolling lookback
  # window, classifying each historical trade's regime retroactively from its entry
  # timestamp via Live::TimeRegimeService#current_regime(time:). Entries::Guards::
  # SegmentExpectancyGuard consults #negative_edge? to throttle entries into segments
  # that have a statistically meaningful sample AND a clearly negative realized edge —
  # closing the loop from "the bot trades the same way regardless of its own track
  # record" to "the bot learns which of its own patterns aren't working and backs off."
  #
  # Config (config/algo.yml under trading.segment_expectancy):
  #   segment_expectancy:
  #     lookback_days: 14
  #     min_samples: 8            # below this, a segment is "unproven" — never blocks
  #     negative_expectancy_rupees: -150.0  # avg realized PnL/trade below this → negative edge
  #     cache_ttl_minutes: 15
  class SegmentExpectancyAnalyzer
    include Singleton

    DEFAULT_LOOKBACK_DAYS = 14
    DEFAULT_MIN_SAMPLES = 8
    DEFAULT_NEGATIVE_EXPECTANCY_RUPEES = -150.0
    DEFAULT_CACHE_TTL_MINUTES = 15

    # @return [Hash, nil] { sample_size:, win_rate:, expectancy_rupees:, total_pnl_rupees: }
    #   or nil when there isn't a meaningful sample for this segment yet.
    def segment_stats(index_key:, regime:)
      return nil if index_key.blank? || regime.blank?

      Rails.cache.fetch(cache_key(index_key, regime), expires_in: cache_ttl_minutes.minutes) do
        compute_segment_stats(index_key: index_key, regime: regime)
      end
    rescue StandardError => e
      Rails.logger.warn("[SegmentExpectancyAnalyzer] segment_stats error: #{e.class} - #{e.message}")
      nil
    end

    # True only when the segment has enough realized samples to be statistically
    # meaningful AND its realized expectancy is clearly negative — an "unproven" or
    # merely break-even segment never blocks (avoids self-fulfilling cold-start bans).
    def negative_edge?(index_key:, regime:)
      stats = segment_stats(index_key: index_key, regime: regime)
      return false unless stats
      return false if stats[:sample_size] < min_samples

      stats[:expectancy_rupees] < negative_expectancy_rupees
    end

    private

    def compute_segment_stats(index_key:, regime:)
      positions = position_scope
                  .where(status: :exited)
                  .where("meta->>'index_key' = ?", index_key)
                  .where(exited_at: lookback_days.days.ago..Time.current)
                  .where.not(last_pnl_rupees: nil)

      regime_service = Live::TimeRegimeService.instance
      segment = positions.select { |p| p.created_at && regime_service.current_regime(time: p.created_at) == regime }

      return nil if segment.empty?

      pnls = segment.map { |p| p.last_pnl_rupees.to_f }
      winners = pnls.count(&:positive?)

      {
        sample_size: pnls.size,
        win_rate: (winners.to_f / pnls.size).round(4),
        expectancy_rupees: (pnls.sum / pnls.size).round(2),
        total_pnl_rupees: pnls.sum.round(2)
      }
    end

    def position_scope
      paper_trading_mode? ? PositionTracker.paper : PositionTracker.live
    end

    def paper_trading_mode?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue StandardError
      false
    end

    def cache_key(index_key, regime)
      "trading:segment_expectancy:#{index_key}:#{regime}:#{lookback_days}"
    end

    def lookback_days
      cfg.fetch(:lookback_days, DEFAULT_LOOKBACK_DAYS).to_i
    end

    def min_samples
      cfg.fetch(:min_samples, DEFAULT_MIN_SAMPLES).to_i
    end

    def negative_expectancy_rupees
      cfg.fetch(:negative_expectancy_rupees, DEFAULT_NEGATIVE_EXPECTANCY_RUPEES).to_f
    end

    def cache_ttl_minutes
      cfg.fetch(:cache_ttl_minutes, DEFAULT_CACHE_TTL_MINUTES).to_i
    end

    def cfg
      AlgoConfig.fetch.dig(:trading, :segment_expectancy) || {}
    rescue StandardError
      {}
    end
  end
end
