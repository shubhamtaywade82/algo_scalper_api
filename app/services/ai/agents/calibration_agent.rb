# frozen_string_literal: true

module Ai
  module Agents
    # Blueprint §8.8 "Calibration Agent" — replaces the manual-only trigger
    # for Ai::Calibration::Runner (rake ai:calibrate, or the Autonomous
    # Orchestrator, neither scheduled in config/recurring.yml today) with a
    # rolling "N new closed trades since the last run" check.
    #
    # Level 1 (Advisor): by default this only reports whether calibration
    # should run (auto_run: false). Even when auto_run: true triggers
    # Ai::Calibration::Runner, that Runner still produces a CalibrationRun
    # that requires an explicit human #apply! — this agent cannot change a
    # live trading parameter on its own either way.
    class CalibrationAgent < BaseAgent
      DEFAULT_TRIGGER_TRADES = 10
      DEFAULT_LOOKBACK_DAYS = 30

      private

      def perform(symbol:, trigger_trades: DEFAULT_TRIGGER_TRADES, auto_run: false)
        symbol = symbol.to_s.upcase
        last_run = CalibrationRun.where(symbol: symbol).order(created_at: :desc).first
        since = last_run&.created_at || DEFAULT_LOOKBACK_DAYS.days.ago
        new_trade_count = TradeAnalytic.where(symbol: symbol).where(created_at: since..).count
        should_run = new_trade_count >= trigger_trades

        run = should_run && auto_run ? safe_run(symbol) : nil

        {
          decision_type: 'calibration_trigger_check',
          confidence: should_run ? 0.8 : 0.2,
          output: {
            symbol: symbol,
            new_trades_since_last_run: new_trade_count,
            trigger_threshold: trigger_trades,
            should_run_calibration: should_run,
            last_calibration_run_at: last_run&.created_at,
            auto_run_triggered: run.present?,
            calibration_run_id: run&.id
          }
        }
      end

      def safe_run(symbol)
        Ai::Calibration::Runner.call(symbol: symbol, days: DEFAULT_LOOKBACK_DAYS)
      rescue StandardError => e
        Rails.logger.error("[Ai::Agents::CalibrationAgent] Runner.call failed for #{symbol}: #{e.message}")
        nil
      end
    end
  end
end
