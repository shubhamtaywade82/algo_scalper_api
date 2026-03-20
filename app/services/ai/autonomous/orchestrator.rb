# frozen_string_literal: true

module Ai
  module Autonomous
    # The "System Brain" that orchestrates the Observe-Think-Act loop.
    # Uses LLM to diagnose performance leaks and select the optimal remediation tool.
    class Orchestrator
      # Map of human-friendly strategies to actual solvers/rakes
      SOLVERS = {
        'calibration' => ->(symbol, days) { Ai::Calibration::Runner.call(symbol: symbol, days: days) },
        'indicator_tuning' => ->(symbol, _days) { run_indicator_optimizer(symbol) },
        'trailing_optimization' => ->(symbol, _days) { run_trailing_optimizer(symbol) }
      }.freeze

      def self.call(symbol:, days: 30)
        new(symbol: symbol, days: days).call
      end

      def initialize(symbol:, days:)
        @symbol = symbol.upcase
        @days   = days
      end

      def call
        Rails.logger.info("[Orchestrator] 🧠 Starting Autonomous Optimization for #{@symbol}")

        # 1. OBSERVE: Run Audit
        audit_report = Ai::Autonomous::Auditor.report(symbol: @symbol, days: @days)

        if audit_report[:performance][:total_trades].to_i < 5
          Rails.logger.warn("[Orchestrator] ⚠️ Insufficient trade data for #{@symbol} audit")
          return { status: :skipped, reason: 'insufficient_data' }
        end

        # 2. THINK: Ask AI for strategy
        strategy = decide_strategy(audit_report)

        Rails.logger.info("[Orchestrator] 🎯 AI Selected Strategy: #{strategy['selected_solver']} - #{strategy['reasoning']}")

        # 3. ACT: Execute Solver
        solver_key = strategy['selected_solver']
        if SOLVERS.key?(solver_key)
          result = SOLVERS[solver_key].call(@symbol, @days)
          { 
            status: :success, 
            strategy: strategy, 
            solver_result: result,
            audit: audit_report
          }
        else
          Rails.logger.error("[Orchestrator] ❌ Unknown solver selected: #{solver_key}")
          { status: :error, reason: 'unknown_solver' }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] ❌ Failed: #{e.message}")
        { status: :error, message: e.message }
      end

      class << self
        private

        def run_indicator_optimizer(symbol)
          instrument = Instrument.find_by!(symbol_name: symbol)
          # Run for ADX first as it's the most common signal bottleneck
          Optimization::SingleIndicatorOptimizer.new(
            instrument: instrument,
            interval: '5',
            indicator: :adx,
            lookback_days: 30
          ).run
        end

        def run_trailing_optimizer(symbol)
          Optimization::TrailingOptimizer.new(index_key: symbol).optimize
        end
      end

      private

      def decide_strategy(audit_report)
        prompt = <<~PROMPT
          You are the Meta-Orchestrator for an Autonomous Trading System.
          Analyze the following Audit Report for #{@symbol} and select the best optimization tool.

          AUDIT REPORT:
          #{JSON.pretty_generate(audit_report)}

          AVAILABLE TOOLS:
          1. "calibration": General adjustment of SL/TP/Entry Filters using Ollama. (Best for risk management issues).
          2. "indicator_tuning": Retuning ADX/Supertrend/RSI parameters. (Best for signal accuracy/win rate issues).
          3. "trailing_optimization": Fine-tuning trailing stop-loss based on MFE/MAE. (Best for profit capture issues).

          STRICT OUTPUT RULES:
          Return ONLY JSON with:
          - "selected_solver": One of [calibration, indicator_tuning, trailing_optimization]
          - "reasoning": Why this tool is best for the current problems
          - "expected_outcome": What metric you expect to improve

          JSON:
        PROMPT

        response = Services::Ai::OpenaiClient.new.generate(prompt: prompt)
        JSON.parse(response.gsub(/```json|```/, '').strip)
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Strategy decision failed: #{e.message}")
        { 'selected_solver' => 'calibration', 'reasoning' => "Fallback to broad calibration due to error: #{e.message}" }
      end
    end
  end
end
