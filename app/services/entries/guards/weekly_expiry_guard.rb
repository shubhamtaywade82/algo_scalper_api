# frozen_string_literal: true

module Entries
  module Guards
    class WeeklyExpiryGuard
      include BaseGuard

      def self.call(context)
        new(context).call
      end

      def initialize(context)
        @context = context
        @index_cfg = context[:index_cfg]
        @pick = context[:pick]
        @is_supertrend = context[:is_supertrend] || context[:entry_metadata]&.dig(:entry_contract).to_s == Entries::EntryGuard::SUPERTREND_CONTRACT
        @is_paper = context[:is_paper]
      end

      def call
        return PASS if @is_supertrend || @is_paper

        symbol = @index_cfg[:key].to_s.upcase
        return PASS unless %w[NIFTY SENSEX].include?(symbol)

        if weekly_contract?(pick: @pick, index_cfg: @index_cfg)
          PASS
        else
          { blocked: 'weekly_only_expiry_rule' }
        end
      end

      private

      def weekly_contract?(pick:, index_cfg:)
        instrument = Instruments::LegacyResolver.resolve_pick(pick)
        return false unless instrument

        # During monthly expiry weeks, the nearest contract is flagged 'M', replacing the weekly.
        instrument.expiry_flag.to_s.upcase.start_with?('W') ||
          (instrument.expiry_date.present? && instrument.expiry_date <= Time.zone.today + Signal::ExpiryGate.max_expiry_days.days)
      rescue StandardError
        false
      end
    end
  end
end
