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
        derivative = if pick[:derivative_id].present?
                       Derivative.find_by(id: pick[:derivative_id])
                     else
                       Derivative.find_by(
                         security_id: pick[:security_id].to_s,
                         segment: (pick[:segment] || index_cfg[:segment]).to_s
                       )
                     end
        return false unless derivative

        derivative.expiry_flag.to_s.upcase.start_with?('W')
      rescue StandardError
        false
      end
    end
  end
end
