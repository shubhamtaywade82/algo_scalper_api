# frozen_string_literal: true

module Ai
  module Calibration
    # Orchestrates the full AI calibration pipeline:
    #
    #   DatasetBuilder → PromptBuilder → OllamaClient#generate
    #     → ResultParser → BacktestValidator → ConfigApplier
    #
    # Usage:
    #   run = Ai::Calibration::Runner.call(symbol: 'NIFTY', days: 30)
    #   # => CalibrationRun or nil (on failure / insufficient data)
    #
    # The returned CalibrationRun holds `proposed_patch` but is NOT applied.
    # A human must call run.apply!(applied_by: 'who') to activate changes.
    class Runner
      # Minimum paper trades required before invoking Ollama.
      MIN_TRADES = 20

      class InsufficientDataError < StandardError; end

      def self.call(symbol:, days: 30, dry_run: false)
        new(symbol: symbol, days: days, dry_run: dry_run).call
      end

      def initialize(symbol:, days:, dry_run: false)
        @symbol  = symbol.to_short_name.upcase rescue symbol.to_s.upcase
        @days    = days.to_i
        @dry_run = dry_run
      end

      def call
        log "Starting calibration pipeline (days=#{@days})"

        # 1. Build dataset
        dataset = DatasetBuilder.call(symbol: @symbol, days: @days)
        trade_count = dataset[:trades].size

        if trade_count < MIN_TRADES
          raise InsufficientDataError,
                "#{@symbol}: #{trade_count} trades < MIN_TRADES (#{MIN_TRADES}). " \
                "Collect more paper trades before calibrating."
        end

        log "Dataset ready — #{trade_count} trades, win_rate=#{dataset[:meta][:win_rate]}%"

        # 2. Build prompt
        prompt = PromptBuilder.call(dataset: dataset)

        # 3. Call Ollama via centralized OllamaClient with schema-enforced output
        raw = call_ai_generate(prompt)

        unless raw
          log "AI returned nil — model error or timeout", :error
          return nil
        end

        log "AI response received"

        # 4. Parse + validate AI response
        parsed = ResultParser.call(raw)
        log "Parsed #{parsed[:parameter_changes].size} parameter changes"

        if parsed[:proposed_patch].blank?
          log "No actionable parameter changes after filtering"
          return nil
        end

        # 5. Backtest validation
        validation = BacktestValidator.call(
          trades:         dataset[:trades],
          proposed_patch: parsed[:proposed_patch]
        )

        unless validation[:approved]
          log "BacktestValidator rejected — #{validation[:rejection_reason]}", :warn
          return nil
        end

        log "Backtest approved — baseline PnL ₹#{validation[:baseline_pnl]}, " \
            "projected ₹#{validation[:projected_pnl]} (delta ₹#{validation[:pnl_delta]})"

        # 6. Persist CalibrationRun (does NOT apply)
        run = ConfigApplier.call(
          symbol:            @symbol,
          parsed_result:     parsed,
          validation_result: validation,
          dataset_meta:      dataset[:meta],
          dry_run:           @dry_run
        )

        log "CalibrationRun ##{run&.id} persisted."
        run

      rescue InsufficientDataError => e
        Rails.logger.warn("[AiCalibration::Runner] #{e.message}")
        nil
      rescue StandardError => e
        log "Unexpected error — #{e.class}: #{e.message}", :error
        Rails.logger.debug { e.backtrace.first(5).join("\n") }
        nil
      end

      private

      def call_ai_generate(prompt)
        client = Services::Ai::OllamaClient.instance
        return nil unless client.enabled?

        schema_path = Rails.root.join('config', 'ai_calibration_schema.json')
        schema      = JSON.parse(File.read(schema_path))

        # Use the specific model prioritized for calibration if set
        model = ENV['AI_CALIBRATION_MODEL'] || client.preferred_text_model

        client.generate(
          prompt: prompt,
          model:  model,
          schema: schema
        )
      rescue StandardError => e
        log "AI Generation failed: #{e.message}", :error
        nil
      end

      def log(msg, level = :info)
        Rails.logger.public_send(level, "[AiCalibration::Runner] #{@symbol}: #{msg}")
      end
    end
  end
end
