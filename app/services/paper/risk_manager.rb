# frozen_string_literal: true

module Paper
  class RiskManager
    class << self
      def update_all_positions!
        PaperPosition.where(status: PaperPosition::STATUSES[:active]).includes(:instrument).find_each do |pos|
          ltp = TickCache.instance.ltp(pos.segment || pos.instrument.segment, pos.security_id)
          next unless ltp

          pos.update_pnl!(ltp)
        end
      end

      def enforce_hard_limits!(sl_pct:, tp_pct:)
        PaperPosition.where(status: PaperPosition::STATUSES[:active]).find_each do |pos|
          next if pos.current_price.blank?

          invested = BigDecimal(pos.entry_price.to_s) * pos.quantity
          pnl = BigDecimal(pos.pnl_rupees.to_s)
          pnl_pct = invested.zero? ? 0 : (pnl / invested)

          if pnl_pct <= -sl_pct.to_d
            close_position!(pos)
          elsif pnl_pct >= tp_pct.to_d
            close_position!(pos)
          end
        end
      end

      def close_position!(pos)
        seg = pos.segment || pos.instrument.segment
        ltp = TickCache.instance.ltp(seg, pos.security_id) || pos.current_price || pos.entry_price
        net = pos.exit!(exit_price: ltp, brokerage: 0)
        PaperWallet.wallet.release!(pos.entry_price * pos.quantity)
        PaperWallet.wallet.book_pnl!(net)
      end
    end
  end
end
