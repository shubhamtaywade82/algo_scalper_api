# frozen_string_literal: true

module Orders
  # Dynamic MFE Capture Exit Engine for weekly index options (NIFTY/SENSEX)
  # Captures profits based on Maximum Favorable Excursion (MFE) retrace
  class MfeExitEngine
    CONFIG = {
      nifty: {
        retrace_ratio: 0.35
      },
      sensex: {
        retrace_ratio: 0.45
      }
    }.freeze

    def initialize(position:, ltp:, entry_price: nil, highest_price: nil)
      @position = position
      @ltp = ltp.to_f
      @entry_price = (entry_price || position.entry_price).to_f
      @highest = (highest_price || position.highest_price || @entry_price).to_f
    end

    def call
      update_extremes

      cfg = config

      mfe = @highest - @entry_price

      return nil if mfe <= 0

      # Exit when price drops X% from peak profit (MFE)
      # SL = highest_price - (MFE * retrace_ratio)
      stop_price = @highest - (mfe * cfg[:retrace_ratio])

      stop_price.round(2)
    end

    alias stop call

    private

    def config
      symbol = @position.symbol.to_s.upcase
      if symbol.include?('SENSEX')
        CONFIG[:sensex]
      else
        CONFIG[:nifty]
      end
    end

    def update_extremes
      updated = false
      meta = (@position.meta || {}).dup

      if @ltp > @highest
        @highest = @ltp
        meta['highest_price'] = @highest
        updated = true
      end

      # Track lowest_price as well (for analytics/future use)
      lowest = (meta['lowest_price'] || @entry_price).to_f
      if @ltp < lowest
        meta['lowest_price'] = @ltp
        updated = true
      end

      if updated
        if @position.respond_to?(:update_columns)
          @position.update_columns(meta: meta)
        elsif @position.respond_to?(:meta=)
          @position.meta = meta
        end
      end
    end
  end
end
