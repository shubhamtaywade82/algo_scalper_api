# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.7 "Post-Trade Analysis Agent" — this is the functional
    # replacement for TradingBot::SelfLearning, which was a stub
    # (fetch_recent_closed_trades hardcoded to return [], lessons only ever
    # logged via Rails.logger, never persisted). This agent runs on demand
    # (not from a PositionTracker callback — the exit hot path is left
    # untouched), finds exited positions without a TradeMemory yet, and
    # persists a structured lesson per trade using real TradeAnalytic data
    # (max favorable/adverse excursion) that Optimization::TradeAnalyzer
    # already computes on every exit.
    class PostTradeAnalysisAgent < BaseAgent
      DEFAULT_BATCH_SIZE = 20

      private

      def perform(batch_size: DEFAULT_BATCH_SIZE)
        trackers = PositionTracker.exited
                                  .left_joins(:trade_memory)
                                  .where(trade_memories: { id: nil })
                                  .order(exited_at: :desc)
                                  .limit(batch_size)

        created = trackers.filter_map { |tracker| build_lesson(tracker) }

        {
          decision_type: 'post_trade_lessons',
          confidence: created.empty? ? 0.0 : 1.0,
          published_event: created.any? ? 'trade_lesson' : nil,
          output: { processed: created.size, symbols: created.map(&:symbol).uniq }
        }
      end

      def build_lesson(tracker)
        analytic = tracker.trade_analytic
        entry_quality = entry_quality_score(tracker, analytic)
        exit_efficiency = exit_efficiency_pct(tracker, analytic)
        lesson_text, category = describe(tracker, entry_quality, exit_efficiency)

        memory = TradeMemory.create!(
          position_tracker: tracker,
          trade_analytic: analytic,
          symbol: tracker.symbol,
          strategy_name: tracker.entry_strategy,
          regime_at_exit: tracker.profit_zone_state,
          entry_quality_score: entry_quality,
          exit_efficiency_pct: exit_efficiency,
          pnl_rupees: tracker.last_pnl_rupees,
          exit_reason: tracker.exit_reason,
          lesson: lesson_text,
          category: category,
          confidence: 0.6
        )

        publish(:trade_lesson, {
                  position_tracker_id: tracker.id, symbol: tracker.symbol,
                  category: category, pnl_rupees: tracker.last_pnl_rupees.to_f
                })
        memory
      rescue StandardError => e
        Rails.logger.error("[Ai::Agents::PostTradeAnalysisAgent] failed for tracker=#{tracker.id}: #{e.message}")
        nil
      end

      # MFE-based capture efficiency: how much of the best available move
      # (from entry to the intracandle high/low) the exit actually captured.
      def exit_efficiency_pct(tracker, analytic)
        return nil unless analytic && tracker.entry_price.present? && tracker.exit_price.present?

        entry = tracker.entry_price.to_f
        exit_p = tracker.exit_price.to_f
        best_excursion = tracker.long_position? ? analytic.max_favorable_excursion.to_f : analytic.max_adverse_excursion.to_f.abs
        return nil if best_excursion.zero?

        captured = tracker.long_position? ? (exit_p - entry) : (entry - exit_p)
        ((captured / best_excursion) * 100).round(2)
      end

      # Heuristic proxy for entry timing quality: how deep the position went
      # underwater (MAE) relative to entry price before recovering/exiting.
      # A large adverse excursion suggests the entry was taken too early/late
      # relative to the move that ultimately played out.
      def entry_quality_score(tracker, analytic)
        return nil unless analytic
        return nil if tracker.entry_price.to_f.zero?

        drawdown_pct = (analytic.max_adverse_excursion.to_f.abs / tracker.entry_price.to_f) * 100
        [100 - (drawdown_pct * 5), 0].max.round(2)
      end

      def describe(tracker, entry_quality, exit_efficiency)
        pnl = tracker.last_pnl_rupees.to_f
        category = category_for(pnl, entry_quality, exit_efficiency)
        text = "#{tracker.symbol} #{tracker.entry_strategy || 'unknown-strategy'}: " \
               "pnl=#{pnl.round(2)} exit_reason=#{tracker.exit_reason || 'unknown'} " \
               "entry_quality=#{entry_quality.nil? ? 'n/a' : entry_quality} " \
               "exit_efficiency=#{exit_efficiency.nil? ? 'n/a' : "#{exit_efficiency}%"}"
        [text, category]
      end

      def category_for(pnl, entry_quality, exit_efficiency)
        if pnl.negative? && entry_quality && entry_quality < 40
          'entry_timing'
        elsif pnl.positive? && exit_efficiency && exit_efficiency < 50
          'exit_execution'
        elsif pnl.negative?
          'risk_management'
        else
          'pattern_recognition'
        end
      end
    end
  end
end
