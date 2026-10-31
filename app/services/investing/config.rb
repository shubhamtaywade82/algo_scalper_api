# frozen_string_literal: true

module Investing
  # Reader for config/investing.yml (TDD §5).
  #
  # ISOLATION GUARANTEE: this configuration never reads or writes
  # config/algo.yml / AlgoSetting — the intraday trading paper/live switch and
  # the investing execution mode are separate keys in separate files (hard
  # boundary #2). Flipping one cannot flip the other; verified by
  # spec/services/investing/config_spec.rb.
  #
  # Live mode is deliberately hard to arm: it additionally requires
  # INVESTING_LIVE_CONFIRMED='I Understand' in the environment, so a YAML edit
  # alone can never enable live order submission.
  class Config
    MODES = %w[paper live].freeze
    LIVE_CONFIRMATION_PHRASE = "I Understand"
    LIVE_CONFIRMATION_ENV = "INVESTING_LIVE_CONFIRMED"

    class ConfigurationError < StandardError; end

    class << self
      # @return [Boolean] master switch for the whole Investing domain
      def enabled? = !!raw.fetch(:enabled, false)

      # Effective execution mode after the confirmation guard: a configured
      # 'live' without the env confirmation stays paper (TDD §5.2 rule 2).
      # @return [String] "paper" | "live"
      def execution_mode = live? ? "live" : "paper"

      def live? = configured_mode == "live" && confirmation_present?
      def paper? = !live?

      def require_approval = !!raw.dig(:execution, :require_approval)
      def automatic_execution? = !!raw.dig(:execution, :automatic_execution)
      def allow_margin? = !!raw.dig(:execution, :allow_margin)
      def allow_derivatives? = !!raw.dig(:execution, :allow_derivatives)

      def max_order_value = raw.dig(:execution, :max_order_value_inr)
      def max_orders_per_day = raw.dig(:execution, :max_orders_per_day)
      def price_staleness_seconds = raw.dig(:execution, :price_staleness_seconds)

      # @return [Hash] the mandates section (mandate_key => mandate hash)
      def mandates = raw.fetch(:mandates, {})

      # Boot-time validation (TDD §5.2 rule 3): require_approval cannot be
      # disabled while mode is live — fail-closed at load, mirroring the
      # repo's Ai::OpenaiClient discipline.
      def validate!(config)
        mode = config.dig(:execution, :mode).to_s
        unless MODES.include?(mode)
          raise ConfigurationError,
                "investing.execution.mode must be one of #{MODES.join(', ')} (got #{mode.inspect})"
        end

        return unless mode == "live"
        return if config.dig(:execution, :require_approval) != false

        raise ConfigurationError,
              "investing.execution.require_approval cannot be false while mode is live"
      end

      private

      def configured_mode = raw.dig(:execution, :mode).to_s

      def confirmation_present?
        ENV[LIVE_CONFIRMATION_ENV] == LIVE_CONFIRMATION_PHRASE
      end

      def raw
        Rails.application.config.x.investing || {}
      end
    end
  end
end
