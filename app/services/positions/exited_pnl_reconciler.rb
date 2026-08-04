# frozen_string_literal: true

module Positions
  class ExitedPnlReconciler < ApplicationService
    TOLERANCE_RUPEES = 1.0
    PCT_TOLERANCE = BigDecimal('0.0001')
    DEFAULT_LOOKBACK = 7.days

    def initialize(tracker: nil, since: DEFAULT_LOOKBACK.ago)
      @tracker = tracker
      @since = since
    end

    def call
      return reconcile_tracker(tracker) if tracker

      reconcile_batch
    end

    private

    attr_reader :tracker, :since

    def reconcile_batch
      stats = { scanned: 0, fixed: 0, aligned: 0 }

      candidates.find_each do |candidate|
        stats[:scanned] += 1
        result = reconcile_tracker(candidate)
        stats[:fixed] += 1 if result[:fixed]
        stats[:aligned] += 1 unless result[:fixed]
      end

      stats
    end

    def candidates
      PositionTracker.exited
                     .where(exited_at: since..)
                     .where.not(exit_price: nil)
                     .where.not(entry_price: nil)
                     .where('quantity > 0')
    end

    def reconcile_tracker(tracker)
      truth = truth_snapshot(tracker)
      return { fixed: false, reason: :no_truth } unless truth

      return { fixed: false, reason: :aligned } unless drifted?(tracker, truth)

      before = {
        pnl: tracker.last_pnl_rupees,
        pnl_pct: tracker.last_pnl_pct
      }

      apply_truth!(tracker, truth)
      Live::RedisPnlCache.instance.clear_tracker(tracker.id)

      Rails.logger.info(
        "[ExitedPnlReconciler] Fixed tracker #{tracker.id} (#{tracker.order_no}): " \
        "pnl #{before[:pnl].to_f.round(2)} -> #{truth[:pnl].to_f.round(2)}"
      )

      { fixed: true, before: before, after: { pnl: truth[:pnl], pnl_pct: truth[:pnl_pct] } }
    rescue StandardError => e
      Rails.logger.error(
        "[ExitedPnlReconciler] Failed tracker #{tracker.id}: #{e.class} - #{e.message}"
      )
      { fixed: false, reason: :error, error: e.message }
    end

    def truth_snapshot(tracker)
      FinalPnl.from_exit_price(
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        exit_price: tracker.exit_price,
        is_exited: true
      )
    end

    def drifted?(tracker, truth)
      pnl_drift = (tracker.last_pnl_rupees.to_f - truth[:pnl].to_f).abs
      return true if pnl_drift > TOLERANCE_RUPEES

      stored_pct = tracker.last_pnl_pct
      return false if stored_pct.blank?

      (BigDecimal(stored_pct.to_s) - truth[:pnl_pct]).abs > PCT_TOLERANCE
    end

    def apply_truth!(tracker, truth)
      tracker.with_lock do
        tracker.reload
        execution_meta = tracker.execution.is_a?(Hash) ? tracker.execution.deep_dup : {}
        display_pct = (truth[:pnl_pct].to_f * 100.0).round(2)

        execution_meta['final_pnl_pct'] = display_pct
        execution_meta['classified_as'] = classify_exit(display_pct)

        tracker.update!(
          last_pnl_rupees: truth[:pnl],
          last_pnl_pct: truth[:pnl_pct],
          execution: execution_meta
        )
      end
    end

    def classify_exit(display_pct)
      return 'profit' if display_pct.positive?
      return 'loss' if display_pct.negative?

      'breakeven'
    end
  end
end
