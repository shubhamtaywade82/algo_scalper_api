# frozen_string_literal: true

module Ai
  module Autonomous
    # The "System Brain" that orchestrates the Observe-Think-Act loop.
    # Uses LLM to diagnose performance leaks and select the optimal remediation tool.
    class Orchestrator
      def self.call(symbol:, days: 30, dry_run: false)
        new(symbol: symbol, days: days, dry_run: dry_run).call
      end

      def initialize(symbol:, days:, dry_run: false)
        @symbol  = symbol.to_s.upcase
        @days    = days.to_i
        @dry_run = dry_run
      end

      def call
        Rails.logger.info("[Orchestrator] 🧠 Starting Autonomous Optimization for #{@symbol} (Dry Run: #{@dry_run})")

        # 1. OBSERVE: Run Audit
        audit_report = Ai::Autonomous::Auditor.report(symbol: @symbol, days: @days)

        if audit_report[:performance][:total_trades].to_i < 5
          Rails.logger.warn("[Orchestrator] ⚠️ Insufficient trade data for #{@symbol} audit")
          return { status: :skipped, reason: 'insufficient_data' }
        end

        # 2. THINK: Ask AI for strategy
        strategy = decide_strategy(audit_report)

        Rails.logger.info("[Orchestrator] 🎯 AI Selected Strategy: #{strategy['selected_solver']} - #{strategy['reasoning']}")

        # 3. ACT: Execute Solver via TaskRunner
        solver_key = strategy['selected_solver']
        
        result = TaskRunner.run(solver_key, @symbol, @days, dry_run: @dry_run)
        
        { 
          status: :success, 
          strategy: strategy, 
          solver_result: result,
          audit: audit_report,
          dry_run: @dry_run
        }
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] ❌ Failed: #{e.message}")
        { status: :error, message: e.message }
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

        response = Services::Ai::OllamaClient.new.generate(prompt: prompt)
        
        # Robust parsing: find the first { and last }
        json_match = response.match(/\{.*\}/m)
        if json_match
          JSON.parse(json_match[0])
        else
          # Fallback to direct parse if no brackets found (unlikely but safe)
          JSON.parse(response.gsub(/```json|```/, '').strip)
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Strategy decision failed: #{e.message}")
        { 'selected_solver' => 'calibration', 'reasoning' => "Fallback to broad calibration due to error: #{e.message}" }
      end
    end
  end
end
