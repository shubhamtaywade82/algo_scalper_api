# frozen_string_literal: true

module Indicators
  # Ports ta.dmi(length, smoothing) — Pine Script v6
  #
  # Algorithm:
  #   +DM = max(high - prev_high, 0) when > max(prev_low - low, 0), else 0
  #   -DM = max(prev_low - low, 0) when > max(high - prev_high, 0), else 0
  #   TR  = max(high - low, |high - prev_close|, |low - prev_close|)
  #   Smoothed with Wilder's RMA (length)
  #   +DI = 100 * RMA(+DM, len) / RMA(TR, len)
  #   -DI = 100 * RMA(-DM, len) / RMA(TR, len)
  #   DX  = 100 * |+DI - -DI| / (+DI + -DI)
  #   ADX = RMA(DX, smoothing)
  #
  # @return Array<Hash> :diplus, :diminus, :adx (nil for warm-up bars)
  class DMI
    def initialize(length: 14, smoothing: 14)
      @length    = length
      @smoothing = smoothing
    end

    def calculate(bars)
      results = Array.new(bars.size, nil)

      # Accumulators for Wilder's RMA (EMA with alpha = 1/length)
      rma_pdm = rma_ndm = rma_tr = rma_adx = nil
      alpha_dm  = 1.0 / @length
      alpha_adx = 1.0 / @smoothing

      bars.each_with_index do |bar, i|
        next results[i] = {} if i.zero?

        prev        = bars[i - 1]
        high_diff   = bar[:high]  - prev[:high]
        low_diff    = prev[:low]  - bar[:low]

        pdm = (high_diff > low_diff && high_diff > 0) ? high_diff : 0.0
        ndm = (low_diff > high_diff && low_diff > 0)  ? low_diff  : 0.0

        tr = [
          bar[:high] - bar[:low],
          (bar[:high] - prev[:close]).abs,
          (bar[:low]  - prev[:close]).abs
        ].max

        # Wilder's RMA seed on first bar
        if rma_pdm.nil?
          rma_pdm = pdm
          rma_ndm = ndm
          rma_tr  = tr
          results[i] = {}
          next
        end

        rma_pdm = alpha_dm  * pdm + (1 - alpha_dm)  * rma_pdm
        rma_ndm = alpha_dm  * ndm + (1 - alpha_dm)  * rma_ndm
        rma_tr  = alpha_dm  * tr  + (1 - alpha_dm)  * rma_tr

        diplus  = rma_tr.zero? ? 0.0 : 100.0 * rma_pdm / rma_tr
        diminus = rma_tr.zero? ? 0.0 : 100.0 * rma_ndm / rma_tr

        di_sum  = diplus + diminus
        dx      = di_sum.zero? ? 0.0 : 100.0 * (diplus - diminus).abs / di_sum

        rma_adx = if rma_adx.nil?
                    dx
                  else
                    alpha_adx * dx + (1 - alpha_adx) * rma_adx
                  end

        results[i] = {
          diplus:  diplus.round(4),
          diminus: diminus.round(4),
          adx:     rma_adx.round(4)
        }
      end

      results
    end
  end
end