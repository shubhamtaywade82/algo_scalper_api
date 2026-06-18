# frozen_string_literal: true

module Smc
  # Builds the same SMC hash used by {Trading::PermissionResolver} and
  # {Smc::SmcPermissionResolver} from three {Smc::Context} instances (HTF/MTF/LTF).
  class PermissionSnapshot
    class << self
      # @param htf [Smc::Context]
      # @param mtf [Smc::Context]
      # @param ltf [Smc::Context]
      # @return [Hash]
      def from_contexts(htf:, mtf:, ltf:)
        htf_trend = htf.trend
        mtf_struct = mtf.structure.to_h
        ltf_struct = ltf.respond_to?(:internal_structure) ? ltf.internal_structure.to_h : mtf_struct

        structure_state = case htf_trend.to_sym
                          when :range then :range
                          when :bullish, :bearish then :trend
                          else :neutral
                          end

        fvg_data = ltf.respond_to?(:fvg) ? ltf.fvg.to_h : {}
        liquidity_data = ltf.respond_to?(:liquidity) ? ltf.liquidity.to_h : {}
        fvg_active = Array(fvg_data[:active])
        fvg_any = fvg_active.any? || Array(fvg_data[:all_gaps]).any?
        liquidity_h = liquidity_data

        {
          structure_state: structure_state,
          trend: htf_trend,
          bos_recent: mtf_struct[:last_bos].present?,
          displacement: fvg_any,
          liquidity_event_resolved: liquidity_h[:buy_side_taken] == true || liquidity_h[:sell_side_taken] == true,
          active_liquidity_trap: liquidity_h[:equal_highs] == true || liquidity_h[:equal_lows] == true,
          trap_resolved: false,
          follow_through: ltf_struct[:last_bos].present?
        }
      rescue StandardError => e
        Rails.logger.warn("[Smc::PermissionSnapshot] Error building snapshot: #{e.class} - #{e.message}")
        {}
      end
    end
  end
end
