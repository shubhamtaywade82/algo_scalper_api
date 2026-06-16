# frozen_string_literal: true

module OptionsBuying
  # Decides, near end of day, which still-open positions to carry overnight.
  # A position is tagged for carry only when positional mode is active, carry is
  # allowed for its index, and its ROI clears the configured threshold. Tagging is
  # additionally bounded by a book-level budget (max simultaneous carries and max
  # total carried premium outlay) so the overnight book can't balloon — highest-ROI
  # candidates are carried first until the budget is exhausted. Tagged trackers are
  # skipped by the EOD force-close and the next-morning clear; everything else is
  # left for the normal EOD square-off path to close.
  class EodCarryManager
    def self.run!
      new.run!
    end

    def run!
      return [] unless Mode.positional_active?

      trackers = active_trackers.to_a
      positions = existing_carries(trackers)
      notional = positions.sum { |t| notional_of(t) }
      count = positions.size

      carried = []
      eligible_candidates(trackers).each do |tracker|
        amount = notional_of(tracker)
        unless room_for?(count, notional, amount)
          Rails.logger.info("[OptionsBuying::EodCarryManager] carry budget exhausted; skipping #{tracker.order_no}")
          next
        end

        tag_carry!(tracker)
        count += 1
        notional += amount
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

    def existing_carries(trackers)
      trackers.select { |t| already_tagged?(t) }
    end

    # Highest-ROI eligible, untagged trackers first so the budget funds the best carries.
    def eligible_candidates(trackers)
      trackers
        .reject { |t| already_tagged?(t) }
        .select { |t| CarryPolicy.carry_eligible?(t) }
        .sort_by { |t| -t.last_pnl_pct.to_f }
    end

    # Premium outlay tied up by a position.
    def notional_of(tracker)
      (tracker.entry_price.to_f * tracker.quantity.to_i).abs
    end

    def room_for?(count, notional, amount)
      return false if max_carry_positions.positive? && (count + 1) > max_carry_positions
      return false if max_carry_exposure_rupees.positive? && (notional + amount) > max_carry_exposure_rupees

      true
    end

    def max_carry_positions
      Mode.config.dig(:positional, :max_carry_positions).to_i
    end

    def max_carry_exposure_rupees
      Mode.config.dig(:positional, :max_carry_exposure_rupees).to_f
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
