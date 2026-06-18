# frozen_string_literal: true

module Entries
  module Guards
    # Pre-trade Transaction Cost Model gate (options buying).
    #
    # Net edge (premium %) = expected_edge − round-trip cost, where round-trip cost
    # = bid/ask spread + slippage (both sides) + broker fees as a fraction of the
    # premium outlay. Blocks the entry when the edge does not clear the cost by at
    # least the configured buffer. Option premiums are small and spreads/theta are
    # large, so a marginal signal that can't pay for its own friction should not fire.
    class TransactionCostGuard
      include BaseGuard

      DEFAULT_SLIPPAGE_PCT_PER_SIDE = 0.001
      DEFAULT_EXPECTED_EDGE_PCT = 0.30

      def self.call(context)
        return PASS unless enabled?

        ltp = context[:ltp].to_f
        return PASS unless ltp.positive?

        edge = expected_edge_pct(context)
        cost = round_trip_cost_pct(context, ltp)
        net = edge - cost
        return PASS if net >= min_net_edge_pct

        key = context.dig(:index_cfg, :key) || 'index'
        { blocked: "transaction cost exceeds edge for #{key}: " \
                   "edge=#{edge.round(3)} cost=#{cost.round(3)} net=#{net.round(3)}" }
      rescue StandardError => e
        # Cost model is advisory — fail open so a quote/fee glitch never blocks entries.
        Rails.logger.warn("[TransactionCostGuard] #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        OptionsBuying::Mode.config.dig(:execution, :tcm_enabled) == true
      end

      # Expected premium edge the trade aims to capture. A caller may inject a
      # per-signal value via context[:expected_edge_pct]; otherwise use config.
      def self.expected_edge_pct(context)
        injected = context[:expected_edge_pct]
        return injected.to_f if injected

        (OptionsBuying::Mode.config.dig(:execution, :expected_edge_pct) || DEFAULT_EXPECTED_EDGE_PCT).to_f
      end

      def self.round_trip_cost_pct(context, ltp)
        spread_pct(context, ltp) + slippage_pct + fees_pct(context, ltp)
      end

      # Full bid/ask spread (≈ round-trip crossing cost) as a fraction of premium.
      def self.spread_pct(context, ltp)
        pick = context[:pick] || {}
        segment = pick[:segment] || context.dig(:index_cfg, :segment)
        tick = Live::TickQuery.for_security(segment: segment, security_id: pick[:security_id])
        return 0.0 unless tick

        bid = tick.bid.to_f
        ask = tick.ask.to_f
        return 0.0 unless bid.positive? && ask.positive? && ask >= bid

        (ask - bid) / ltp
      end

      # Slippage charged on both entry and exit.
      def self.slippage_pct
        per_side = (OptionsBuying::Mode.config.dig(:execution, :slippage_pct_per_side) || DEFAULT_SLIPPAGE_PCT_PER_SIDE).to_f
        per_side * 2
      end

      # Round-trip broker fees as a fraction of one lot's premium outlay.
      def self.fees_pct(context, ltp)
        fees = AlgoConfig.fetch[:broker_fees] || {}
        return 0.0 unless fees[:enabled] != false

        lot_size = context[:instrument]&.lot_size.to_i
        return 0.0 unless lot_size.positive?

        round_trip_fee = (fees[:fee_per_order] || 0).to_f * 2
        notional = ltp * lot_size
        return 0.0 unless notional.positive?

        round_trip_fee / notional
      end

      def self.min_net_edge_pct
        (OptionsBuying::Mode.config.dig(:execution, :min_net_edge_pct) || 0.0).to_f
      end
    end
  end
end
