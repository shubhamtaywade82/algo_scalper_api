# frozen_string_literal: true

module Entries
  module Guards
    class CompressionSetupGuard
      include BaseGuard

      def self.call(context)
        return PASS unless OptionsBuying::Mode.compression_enabled?
        return PASS unless positional_gate_active?(context)

        instrument = context[:instrument]
        return PASS unless instrument

        return PASS if OptionsBuying::ATRCompressionChecker.compressed?(instrument)

        key = context.dig(:index_cfg, :key) || 'index'
        ratio = OptionsBuying::ATRCompressionChecker.setup_ratio(instrument)
        ratio_label = ratio ? format('%.2f', ratio) : 'n/a'
        { blocked: "compression setup required: #{key} range/ATR=#{ratio_label}" }
      rescue StandardError => e
        # Core entry gate — fail CLOSED: an error must not let a non-setup entry through.
        Rails.logger.error("[CompressionSetupGuard] #{e.class} - #{e.message}")
        { blocked: 'compression guard unavailable' }
      end

      def self.positional_gate_active?(context)
        return false unless OptionsBuying::Mode.positional_active?

        index_key = context.dig(:index_cfg, :key)
        return false unless index_key

        OptionsBuying::CarryPolicy.carry_allowed?(index_key: index_key)
      end
    end
  end
end
