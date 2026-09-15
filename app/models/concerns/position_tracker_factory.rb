# frozen_string_literal: true

module PositionTrackerFactory
  extend ActiveSupport::Concern

  class_methods do
    # Creates (or returns the already-active) tracker for one instrument.
    #
    # @param instrument [Instrument] The TRADED instrument (option, future,
    #   equity or index row itself — post-consolidation the derivative master
    #   lives in instruments).
    # @param watchable [Instrument, Derivative, nil] Polymorphic watch target;
    #   defaults to `instrument`.
    #
    # Tracker FK semantics (unchanged by the consolidation):
    #   watchable ........ the traded contract
    #   instrument ....... the underlying for derivative trades, self otherwise
    def build_or_average!(instrument:, security_id:, segment:, quantity:, entry_price:, side:, symbol:, order_no:,
                          meta: {}, watchable: nil, status: 'active', trade_state: nil)
      sid = security_id.to_s
      seg = segment.to_s

      # 1️⃣ Find active tracker
      active = PositionTracker.active.find_by(segment: seg, security_id: sid)

      if active
        # HARD RULE: No averaging down / no averaging up.
        # If a tracker is already active for this instrument, return it unchanged.
        Rails.logger.warn("[TrackerFactory] Averaging blocked (no-avg rule) -> #{seg}:#{sid} #{active.id}")
        return active
      end

      # 2️⃣ No active tracker → create new one
      Rails.logger.info("[TrackerFactory] Creating NEW tracker for #{seg}:#{sid}")

      resolved_watchable = watchable || instrument
      parent = resolve_parent_instrument(resolved_watchable)

      PositionTracker.create!(
        watchable: resolved_watchable,
        instrument: parent,
        order_no: order_no,
        security_id: sid,
        symbol: symbol,
        segment: seg,
        side: side,
        quantity: quantity,
        entry_price: entry_price,
        avg_price: entry_price,
        status: status,
        meta: meta,
        trade_state: trade_state
      )
    end

    private

    # Legacy Derivative rows keep their parent via `derivative.instrument`;
    # consolidated derivative Instruments link via underlying_instrument_id.
    # Everything else (equity/index) parents to itself.
    def resolve_parent_instrument(watchable)
      return watchable.instrument if watchable.is_a?(Derivative)
      return watchable unless watchable.is_a?(Instrument)

      if watchable.derivative?
        watchable.underlying_instrument || watchable
      else
        watchable
      end
    end
  end
end
