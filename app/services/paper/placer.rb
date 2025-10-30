# frozen_string_literal: true

module Paper
  class Placer
    class << self
      # Simulates a BUY order and returns a DhanHQ-compatible response object
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY', price: nil,
                      target_price: nil, stop_loss_price: nil, trailing_jump: nil)
        instrument = Instrument.find_by(security_id: sid.to_s)
        return nil unless instrument

        executed_price = current_ltp(seg, sid)
        return nil unless executed_price

        order_no = build_order_no('BUY', sid)

        paper_order = PaperOrder.transaction do
          order = PaperOrder.create!(
            instrument: instrument,
            order_no: order_no,
            correlation_id: client_order_id,
            security_id: sid.to_s,
            segment: seg,
            symbol: instrument.symbol_name,
            transaction_type: 'BUY',
            order_type: 'MARKET',
            product_type: product_type,
            quantity: qty,
            executed_price: executed_price,
            status: PaperOrder::STATUSES[:executed]
          )

          # Allocate capital from wallet
          PaperWallet.wallet.allocate!(executed_price * qty)

          order
        end

        # Return a mock order object that mimics DhanHQ::Models::Order
        mock_order_response(paper_order)
      end

      def sell_market!(seg:, sid:, qty:, client_order_id:, product_type: 'INTRADAY')
        # Find matching PositionTracker for this paper position
        tracker = PositionTracker.active.find_by(security_id: sid.to_s)
        return nil unless tracker

        instrument = Instrument.find_by(security_id: sid.to_s)
        return nil unless instrument

        executed_price = current_ltp(seg, sid)
        return nil unless executed_price

        order_no = build_order_no('SELL', sid)

        paper_order = PaperOrder.transaction do
          order = PaperOrder.create!(
            instrument: instrument,
            order_no: order_no,
            correlation_id: client_order_id,
            security_id: sid.to_s,
            segment: seg,
            symbol: instrument.symbol_name,
            transaction_type: 'SELL',
            order_type: 'MARKET',
            product_type: product_type,
            quantity: qty,
            executed_price: executed_price,
            status: PaperOrder::STATUSES[:executed]
          )

          # Release capital back to wallet
          investment = BigDecimal(tracker.entry_price.to_s) * tracker.quantity
          PaperWallet.wallet.release!(investment)

          # Calculate PnL
          pnl = (executed_price - tracker.entry_price) * qty
          PaperWallet.wallet.book_pnl!(pnl)

          order
        end

        mock_order_response(paper_order)
      end

      def exit_position!(seg:, sid:, client_order_id:)
        # Find matching PositionTracker
        tracker = PositionTracker.active.find_by(security_id: sid.to_s)
        return nil unless tracker

        executed_price = current_ltp(seg, sid)
        return nil unless executed_price

        instrument = tracker.instrument
        qty = tracker.quantity

        order_no = build_order_no('EXIT', sid)

        paper_order = PaperOrder.transaction do
          order = PaperOrder.create!(
            instrument: instrument,
            order_no: order_no,
            correlation_id: client_order_id,
            security_id: sid.to_s,
            segment: seg,
            symbol: tracker.symbol,
            transaction_type: 'SELL',
            order_type: 'MARKET',
            product_type: 'INTRADAY',
            quantity: qty,
            executed_price: executed_price,
            status: PaperOrder::STATUSES[:executed]
          )

          # Release capital and book PnL
          investment = BigDecimal(tracker.entry_price.to_s) * tracker.quantity
          pnl = (executed_price - tracker.entry_price) * qty
          PaperWallet.wallet.release!(investment)
          PaperWallet.wallet.book_pnl!(pnl)

          order
        end

        mock_order_response(paper_order)
      end

      private

      def current_ltp(seg, sid)
        TickCache.instance.ltp(seg, sid.to_s)&.to_d
      end

      def build_order_no(prefix, sid)
        ts = Time.current.strftime('%Y%m%d%H%M%S')
        "PAPER-#{prefix}-#{sid}-#{ts}"
      end

      # Create a mock order response that mimics DhanHQ::Models::Order
      def mock_order_response(paper_order)
        OpenStruct.new(
          order_id: paper_order.order_no,
          order_status: 'COMPLETE',
          transaction_type: paper_order.transaction_type,
          security_id: paper_order.security_id,
          quantity: paper_order.quantity,
          price: paper_order.executed_price,
          product_type: paper_order.product_type
        )
      end
    end
  end
end
