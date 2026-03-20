# frozen_string_literal: true

module Ai
  module Calibration
    # Builds a structured dataset of paper trades for AI calibration.
    #
    # Joins exited paper PositionTrackers with their corresponding
    # TradeTelemetry (SMC entry metrics) and TradingSignals (ADX/supertrend).
    #
    # Usage:
    #   dataset = Ai::Calibration::DatasetBuilder.call(symbol: 'NIFTY', days: 30)
    #   dataset[:trades]  # Array of trade hashes
    #   dataset[:meta]    # Summary stats (win rate, exit breakdown, etc.)
    class DatasetBuilder
      # Maximum seconds between signal creation and trade entry to consider them correlated.
      SIGNAL_CORRELATION_WINDOW = 120

      def self.call(symbol:, days: 30)
        new(symbol: symbol, days: days).call
      end

      def initialize(symbol:, days:)
        @symbol = symbol.to_s.upcase
        @days   = days.to_i
      end

      def call
        from = @days.days.ago
        trackers = load_trackers(from)

        trades = trackers.filter_map { |t| build_trade_row(t) }

        {
          symbol:   @symbol,
          trades:   trades,
          meta:     build_meta(trades),
          from:     from.iso8601,
          to:       Time.current.iso8601
        }
      end

      private

      def load_trackers(from)
        PositionTracker
          .exited_paper
          .where('symbol LIKE ?', "%#{@symbol}%")
          .where(exited_at: from..)
          .includes(:trade_telemetry)
          .order(:created_at)
      end

      def build_trade_row(tracker)
        telemetry = tracker.trade_telemetry
        meta      = tracker.meta.is_a?(Hash) ? tracker.meta : {}
        signal    = find_signal(tracker)

        {
          symbol:           extract_index_key(tracker, meta),
          option_type:      extract_option_type(tracker),
          entry_price:      tracker.entry_price.to_f,
          exit_price:       tracker.exit_price.to_f,
          last_pnl_rupees:  tracker.last_pnl_rupees.to_f,
          last_pnl_pct:     (tracker.last_pnl_pct.to_f * 100).round(2),
          entry_time:       tracker.created_at&.iso8601,
          exit_time:        tracker.exited_at&.iso8601,
          exit_reason:      meta['exit_reason'] || tracker.exit_reason,
          strategy_name:    meta['entry_strategy'],
          trade_state:      tracker.trade_state,

          # Signal indicators at entry
          adx_value:        signal&.adx_value.to_f,
          supertrend_value: signal&.supertrend_value.to_f,
          signal_direction: signal&.direction,
          confidence_score: signal&.confidence_score.to_f,
          signal_metadata:  signal&.metadata,

          # SMC telemetry (nil if not filled)
          bos_age_at_entry: telemetry&.bos_age_at_entry,
          retrace_pct:      telemetry&.retrace_pct.to_f,
          pullback_candles: telemetry&.pullback_candles,
          max_r_reached:    telemetry&.max_r_reached.to_f,
          exit_r:           telemetry&.exit_r.to_f,
          exit_path:        telemetry&.exit_path,
          entry_tf:         telemetry&.entry_tf,
          htf_tf:           telemetry&.htf_tf,

          # Options Behavior (extracted from Signal metadata)
          gamma_score:      signal&.metadata&.dig('gamma_pressure').to_f,
          gamma_strike:     signal&.metadata&.dig('gamma_ramp_strike'),
          iv_rank:          signal&.metadata&.dig('iv_rank_proxy').to_f,
          theta_risk:       signal&.metadata&.dig('theta_risk_score').to_f
        }
      rescue StandardError => e
        Rails.logger.warn("[DatasetBuilder] Skipping tracker #{tracker.id}: #{e.class} — #{e.message}")
        nil
      end

      # Finds the closest TradingSignal within the correlation window before entry.
      def find_signal(tracker)
        return nil unless tracker.created_at

        index_key = tracker.meta&.dig('index_key')
        scope     = TradingSignal.where(
          signal_timestamp: (tracker.created_at - SIGNAL_CORRELATION_WINDOW)..tracker.created_at
        )
        scope = scope.for_index(index_key) if index_key.present?
        scope.order(signal_timestamp: :desc).first
      end

      def extract_index_key(tracker, meta)
        meta['index_key'] || tracker.symbol&.split(' ')&.first || @symbol
      end

      def extract_option_type(tracker)
        sym = tracker.symbol.to_s.upcase
        if sym.include?('CE')
          'CE'
        elsif sym.include?('PE')
          'PE'
        else
          'UNKNOWN'
        end
      end

      def build_meta(trades)
        return empty_meta if trades.empty?

        total     = trades.size
        wins      = trades.count { |t| t[:last_pnl_rupees].positive? }
        total_pnl = trades.sum { |t| t[:last_pnl_rupees] }

        exit_breakdown = trades.group_by { |t| t[:exit_reason] || 'unknown' }
                               .transform_values(&:size)

        regime_approx = trades.group_by { |t| t[:trade_state] || 'unknown' }
                               .transform_values(&:size)

        ce_trades = trades.select { |t| t[:option_type] == 'CE' }
        pe_trades = trades.select { |t| t[:option_type] == 'PE' }

        {
          total_trades:    total,
          win_rate:        total.positive? ? (wins.to_f / total * 100).round(2) : 0,
          total_pnl:       total_pnl.round(2),
          avg_pnl:         total.positive? ? (total_pnl / total).round(2) : 0,
          winners:         wins,
          losers:          total - wins,
          exit_breakdown:  exit_breakdown,
          regime_approx:   regime_approx,
          ce_count:        ce_trades.size,
          pe_count:        pe_trades.size
        }
      end

      def empty_meta
        {
          total_trades:    0,
          win_rate:        0.0,
          total_pnl:       0.0,
          avg_pnl:         0.0,
          winners:         0,
          losers:          0,
          exit_breakdown:  {},
          regime_approx:   {},
          ce_count:        0,
          pe_count:        0
        }
      end
    end
  end
end
