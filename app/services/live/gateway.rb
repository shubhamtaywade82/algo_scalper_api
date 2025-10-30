# frozen_string_literal: true

# Live Gateway wraps Orders::Placer to provide Orders::Gateway interface
# for live trading via DhanHQ
module Live
  class Gateway < Orders::Gateway
    def place_market(side:, segment:, security_id:, qty:, meta: {})
      case side.to_s.downcase
      when 'buy'
        Orders::Placer.buy_market!(
          seg: segment,
          sid: security_id,
          qty: qty,
          client_order_id: meta[:client_order_id] || generate_client_order_id(segment, security_id, side),
          product_type: meta[:product_type] || 'INTRADAY'
        )
      when 'sell'
        Orders::Placer.sell_market!(
          seg: segment,
          sid: security_id,
          qty: qty,
          client_order_id: meta[:client_order_id] || generate_client_order_id(segment, security_id, side)
        )
      else
        Rails.logger.error("[Live::Gateway] Invalid side: #{side}")
        nil
      end
    end

    def flat_position(segment:, security_id:)
      Orders::Placer.exit_position!(
        seg: segment,
        sid: security_id,
        client_order_id: generate_client_order_id(segment, security_id, 'exit')
      )
    end

    def position(segment:, security_id:)
      # Fetch from DhanHQ Position API
      positions = DhanHQ::Models::Position.active
      pos = positions.find { |p| p.security_id.to_s == security_id.to_s && p.exchange_segment == segment }

      return nil unless pos

      ltp = TickCache.instance.ltp(segment, security_id.to_s)
      entry_price = BigDecimal(pos.buy_avg.to_s) if pos.buy_avg
      qty = pos.net_qty.to_i

      upnl = if entry_price && ltp && qty != 0
               (BigDecimal(ltp.to_s) - entry_price) * qty
             else
               BigDecimal('0')
             end

      {
        qty: qty,
        avg_price: entry_price || BigDecimal('0'),
        upnl: upnl,
        rpnl: BigDecimal('0'), # Realized PnL not directly available from Position API
        last_ltp: ltp ? BigDecimal(ltp.to_s) : (entry_price || BigDecimal('0'))
      }
    rescue StandardError => e
      Rails.logger.error("[Live::Gateway] position failed: #{e.message}")
      nil
    end

    def wallet_snapshot
      # Fetch from DhanHQ Funds API
      funds = DhanHQ::Models::Funds.fetch
      return default_wallet unless funds

      {
        cash: BigDecimal(funds.available.to_s || '0'),
        equity: BigDecimal(funds.available.to_s || '0'), # Simplified
        mtm: BigDecimal('0'), # Not directly available
        exposure: BigDecimal('0') # Would need to calculate from positions
      }
    rescue StandardError => e
      Rails.logger.error("[Live::Gateway] wallet_snapshot failed: #{e.message}")
      default_wallet
    end

    private

    def generate_client_order_id(segment, security_id, side)
      timestamp = Time.current.to_i.to_s[-6..]
      "AS-#{side.upcase[0..2]}-#{security_id}-#{timestamp}"
    end

    def default_wallet
      {
        cash: BigDecimal('0'),
        equity: BigDecimal('0'),
        mtm: BigDecimal('0'),
        exposure: BigDecimal('0')
      }
    end
  end
end

