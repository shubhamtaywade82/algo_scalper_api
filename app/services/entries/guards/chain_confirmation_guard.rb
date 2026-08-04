# frozen_string_literal: true

module Entries
  module Guards
    # Confirms the already-picked strike has live OI/IV/delta support before
    # entry: OI must be building (not flat/declining), IV must sit in a sane
    # band (not a blow-off extreme), and delta must sit in a sane band (not a
    # deep-ITM/far-OTM pick that slipped through strike selection).
    #
    # Reads from Options::ChainWatchRegistry, which points at the already-
    # running per-index Options::ChainWatchService instances — this guard
    # never constructs its own ChainWatchService.
    class ChainConfirmationGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        index_key = context[:index_cfg][:key].to_s.upcase
        snapshot = Options::ChainWatchRegistry.snapshot_for(index_key)
        return PASS if snapshot.nil? || snapshot[:chain_stale]

        pick = context[:pick]
        expected_type = context[:direction].to_s == 'bullish' ? 'CE' : 'PE'
        leg = snapshot[:legs].find { |l| l[:strike] == pick[:strike] && l[:type] == expected_type }
        return PASS unless leg

        if leg[:oi_change].to_i < min_oi_change
          return { blocked: "OI change (#{leg[:oi_change]}) below minimum (#{min_oi_change}) on #{pick[:strike]} #{expected_type}" }
        end

        iv = leg[:iv].to_f
        if iv.positive? && (iv < min_iv || iv > max_iv)
          return { blocked: "IV (#{iv.round(2)}%) outside allowed band [#{min_iv}, #{max_iv}] on #{pick[:strike]} #{expected_type}" }
        end

        delta = leg[:delta].to_f.abs
        if delta.positive? && (delta < min_delta || delta > max_delta)
          return { blocked: "delta (#{delta.round(3)}) outside allowed band [#{min_delta}, #{max_delta}] on #{pick[:strike]} #{expected_type}" }
        end

        PASS
      rescue StandardError => e
        Rails.logger.debug { "[ChainConfirmationGuard] fail-open: #{e.class} - #{e.message}" }
        PASS
      end

      def self.enabled?
        config[:enabled] != false
      end

      def self.min_oi_change
        (config[:min_oi_change] || 0).to_i
      end

      def self.min_iv
        (config[:min_iv] || 8.0).to_f
      end

      def self.max_iv
        (config[:max_iv] || 45.0).to_f
      end

      def self.min_delta
        (config[:min_delta] || 0.25).to_f
      end

      def self.max_delta
        (config[:max_delta] || 0.75).to_f
      end

      def self.config
        AlgoConfig.fetch.dig(:risk, :chain_confirmation_gate) || {}
      end
    end
  end
end
