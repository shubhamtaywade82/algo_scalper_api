# frozen_string_literal: true

module Validators
  class LiquidityGate
    MIN_BID_ASK_SPREAD = 0.50
    MIN_BOOK_QTY = 50

    def initialize(underlying:, direction:, index_cfg:)
      @underlying = underlying
      @direction = direction
      @index_cfg = index_cfg
    end

    def check
      picks = Options::ChainAnalyzer.pick_strikes(
        index_cfg: @index_cfg, direction: @direction
      )
      return { pass: false, reason: "No ATM strike found", strike: nil } if picks.blank?

      pick = picks.first
      depth = MarketDataCache.depth_snapshot(pick[:security_id])

      unless depth
        return {
          pass: true, strike: pick[:strike_price],
          security_id: pick[:security_id], spread: nil,
          reason: "No depth data — allowing entry"
        }
      end

      spread = depth[:spread].to_f
      bid_qty = depth[:best_bid_qty].to_i
      ask_qty = depth[:best_ask_qty].to_i
      qty_ok = bid_qty >= MIN_BOOK_QTY && ask_qty >= MIN_BOOK_QTY
      pass = spread <= MIN_BID_ASK_SPREAD && qty_ok

      {
        pass: pass,
        strike: pick[:strike_price],
        security_id: pick[:security_id],
        spread: spread,
        reason: pass ? "OK" : "spread=#{spread} bid_qty=#{bid_qty} ask_qty=#{ask_qty}"
      }
    end
  end
end
