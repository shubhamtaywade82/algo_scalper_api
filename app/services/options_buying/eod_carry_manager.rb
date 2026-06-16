# frozen_string_literal: true

module OptionsBuying
  # Decides, near end of day, which still-open positions to carry overnight.
  # A position is tagged for carry only when positional mode is active, carry is
  # allowed for its index, and its ROI clears the configured threshold. Tagged
  # trackers are then skipped by the EOD force-close and the next-morning clear.
  # Everything else is left for the normal EOD square-off path to close.
  class EodCarryManager
    def self.run!
      new.run!
    end

    def run!
      return [] unless Mode.positional_active?

      carried = []
      active_trackers.each do |tracker|
        next if already_tagged?(tracker)
        next unless CarryPolicy.carry_eligible?(tracker)

        tag_carry!(tracker)
        carried << tracker.order_no
      end

      Rails.logger.info("[OptionsBuying::EodCarryManager] Carrying #{carried.size} position(s): #{carried.join(', ')}")
      carried
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::EodCarryManager] #{e.class} - #{e.message}")
      []
    end

    private

    def active_trackers
      PositionTracker.active
    end

    def already_tagged?(tracker)
      tracker.carry_mode.to_s == Mode::POSITIONAL
    end

    def tag_carry!(tracker)
      tracker.update!(
        carry_mode: Mode::POSITIONAL,
        carry_marked_at: Time.current.iso8601,
        carry_roi_pct: tracker.last_pnl_pct.to_f
      )
      Rails.logger.info(
        "[OptionsBuying::EodCarryManager] Tagged carry #{tracker.order_no} #{tracker.symbol} " \
        "roi=#{(tracker.last_pnl_pct.to_f * 100).round(2)}%"
      )
    end
  end
end
