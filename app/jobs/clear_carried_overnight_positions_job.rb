# frozen_string_literal: true

# Clears carried-overnight (BTST) positions at the start of each trading day.
# Runs at 9:15 AM; any active position with created_at before today is force-closed
# so intraday trackers never carry across days.
class ClearCarriedOvernightPositionsJob < ApplicationJob
  queue_as :background

  REASON = 'BTST_CLEAR (carried overnight, cleared at start of day)'

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform
    exit_engine = nil
    today_start = Time.zone.today.beginning_of_day
    stale = PositionTracker.active.where(created_at: ...today_start).reject { |t| held_carry?(t) }
    if stale.empty?
      Rails.logger.info('[ClearCarriedOvernightPositionsJob] No carried-overnight positions to clear')
      return
    end

    Rails.logger.info("[ClearCarriedOvernightPositionsJob] Clearing #{stale.size} carried-overnight position(s)")

    router = TradingSystem::OrderRouter.new
    exit_engine = Live::ExitEngine.new(order_router: router)
    exit_engine.start

    stale.each do |tracker|
      execute_exit_with_retry(exit_engine, tracker)
    end
  ensure
    exit_engine&.stop
  end

  private

  # Positional carries with carry still allowed (e.g. not yet expiry day) are
  # intentionally held overnight — skip them. Once carry lapses they fall back in.
  def held_carry?(tracker)
    OptionsBuying::CarryPolicy.carry_still_valid?(tracker)
  rescue StandardError => e
    Rails.logger.warn("[ClearCarriedOvernightPositionsJob] carry check #{e.class} - #{e.message}")
    false
  end

  def execute_exit_with_retry(exit_engine, tracker)
    result = exit_engine.execute_exit(tracker, REASON)

    if result[:reason] == 'exit_already_requested'
      tracker.with_lock do
        tracker.reload
        unless tracker.active? && tracker.exit_requested_at.present?
          return
        end

        Rails.logger.info("[ClearCarriedOvernightPositionsJob] #{tracker.order_no} stuck; clearing intent and retrying")
        # Intentional: bypass validations/callbacks for a narrow BTST clear retry path.
        tracker.update_columns(exit_requested_at: nil, exit_sent_at: nil, exit_coid: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
      tracker.reload
      result = exit_engine.execute_exit(tracker, REASON)
    end

    if result[:success] && result[:reason] != 'exit_already_requested'
      Rails.logger.info("[ClearCarriedOvernightPositionsJob] Cleared #{tracker.order_no} (#{tracker.symbol})")
    elsif !result[:success]
      Rails.logger.error(
        "[ClearCarriedOvernightPositionsJob] Failed #{tracker.order_no}: #{result[:reason]} #{result[:error].inspect}"
      )
    end
  rescue StandardError => e
    Rails.logger.error(
      "[ClearCarriedOvernightPositionsJob] Error clearing #{tracker&.order_no}: #{e.class} - #{e.message}"
    )
  end
end
