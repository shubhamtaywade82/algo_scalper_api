# frozen_string_literal: true

module Ai
  module Calibration
    # Creates a CalibrationRun record with the validated proposed_patch.
    # Does NOT auto-apply — that requires a human calling run.apply!(applied_by: ...)
    # via the Rails console or API.
    #
    # Also sends a Telegram notification and emits a Rails log entry.
    class ConfigApplier
      def self.call(symbol:, parsed_result:, validation_result:, dataset_meta:, dry_run: false)
        new(
          symbol:            symbol,
          parsed_result:     parsed_result,
          validation_result: validation_result,
          dataset_meta:      dataset_meta,
          dry_run:           dry_run
        ).call
      end

      def initialize(symbol:, parsed_result:, validation_result:, dataset_meta:, dry_run: false)
        @symbol            = symbol.to_s.upcase
        @parsed_result     = parsed_result
        @validation_result = validation_result
        @dataset_meta      = dataset_meta
        @dry_run           = dry_run
      end

      def call
        patch = @parsed_result[:proposed_patch]

        if patch.blank?
          Rails.logger.info("[ConfigApplier] #{@symbol}: No high-confidence parameter changes — skipping CalibrationRun creation")
          return nil
        end

        raw_stats = build_raw_stats

        if @dry_run
          Rails.logger.info("[ConfigApplier] [DRY_RUN] #{@symbol}: Would create CalibrationRun with #{patch.keys.size} param changes.")
          Rails.logger.info("[ConfigApplier] [DRY_RUN] Proposed Patch: #{patch.inspect}")
          return nil
        end

        run = CalibrationRun.create!(
          symbol:          @symbol,
          weeks_analyzed:  0, # AI calibration doesn't use weeks; field repurposed as days below via raw_stats
          strike_mode:     'ai_calibration',
          raw_stats:       raw_stats,
          proposed_patch:  patch,
          is_regime_shift: regime_shift?,
          regime_reason:   regime_reason
        )

        Rails.logger.info(
          "[ConfigApplier] #{@symbol}: CalibrationRun ##{run.id} created — " \
          "#{patch.keys.size} top-level param group(s) proposed. " \
          "Baseline PnL ₹#{@validation_result[:baseline_pnl]}, " \
          "Projected ₹#{@validation_result[:projected_pnl]}. " \
          "Apply with: CalibrationRun.find(#{run.id}).apply!()"
        )

        notify_telegram(run)

        run
      rescue StandardError => e
        Rails.logger.error("[ConfigApplier] #{@symbol}: Failed to persist CalibrationRun — #{e.class}: #{e.message}")
        nil
      end

      private

      def build_raw_stats
        {
          source:            'ai_calibration',
          dataset_meta:      @dataset_meta,
          diagnosis:         @parsed_result[:diagnosis],
          parameter_changes: @parsed_result[:parameter_changes],
          entry_filters:     @parsed_result[:entry_filters],
          exit_improvements: @parsed_result[:exit_improvements],
          regime_rules:      @parsed_result[:regime_rules],
          validation:        @validation_result.except(:baseline_metrics, :projected_metrics).merge(
            baseline_metrics:  @validation_result[:baseline_metrics],
            projected_metrics: @validation_result[:projected_metrics]
          )
        }
      end

      def regime_shift?
        rules = @parsed_result[:regime_rules] || []
        rules.any? { |r| r['action'] == 'disable_entries' }
      end

      def regime_reason
        rules = @parsed_result[:regime_rules] || []
        disable_rule = rules.find { |r| r['action'] == 'disable_entries' }
        return nil unless disable_rule

        "Disable entries in #{disable_rule['regime']} regime: #{disable_rule['reason']}"
      end

      def notify_telegram(run)
        return unless defined?(Options::CalibrationNotifier)

        Options::CalibrationNotifier.notify(@symbol, run)
      rescue StandardError => e
        Rails.logger.warn("[ConfigApplier] Telegram notify failed: #{e.message}")
      end
    end
  end
end
