# frozen_string_literal: true

module Positions
  module DrawdownSchedule
    module_function

    def cfg
      @cfg ||= begin
        AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:drawdown] || {}
      rescue StandardError
        {}
      end
    end

    # Returns allowed drawdown percent (e.g. 2.34 => 2.34%)
    # profit_pct: current profit percent (positive, e.g. 5.0 for +5%)
    # index_key: "NIFTY", "BANKNIFTY", "SENSEX" etc
    # Returns nil if profit_pct < activation threshold
    def allowed_upward_drawdown_pct(profit_pct, index_key: nil)
      profit_start = cfg[:profit_min].to_f.nonzero? || 3.0
      profit_end   = cfg[:profit_max].to_f.nonzero? || 30.0
      dd_start     = cfg[:dd_start_pct].to_f.nonzero? || 15.0
      dd_end       = cfg[:dd_end_pct].to_f.nonzero? || 1.0
      k            = cfg[:exponential_k].to_f.nonzero? || 3.0

      return nil if profit_pct.to_f < profit_start

      normalized = [[(profit_pct.to_f - profit_start) / (profit_end - profit_start), 0.0].max, 1.0].min
      raw = dd_end + (dd_start - dd_end) * Math.exp(-k * normalized)

      floor = if index_key && cfg[:index_floors] && cfg[:index_floors][index_key.to_s]
                cfg[:index_floors][index_key.to_s].to_f
              else
                cfg[:dd_end_pct].to_f
              end

      [raw, floor].max.round(4)
    end

    # Dynamic reverse SL when PnL < 0 (below entry)
    # pnl_pct: negative value (e.g. -12.5 for -12.5% loss)
    # seconds_below_entry: time spent below entry price
    # atr_ratio: current ATR ratio (for volatility penalty)
    # Returns allowed loss percent (e.g. 12.5 means -12.5% allowed)
    def reverse_dynamic_sl_pct(pnl_pct, seconds_below_entry: 0, atr_ratio: 1.0)
      return nil if pnl_pct >= 0

      cfg2 = begin
        AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:reverse_loss] || {}
      rescue StandardError
        {}
      end

      return nil unless cfg2[:enabled]

      max_loss = cfg2[:max_loss_pct].to_f.nonzero? || 20.0
      min_loss = cfg2[:min_loss_pct].to_f.nonzero? || 5.0
      span = cfg2[:loss_span_pct].to_f.nonzero? || 30.0

      loss_pct = [-pnl_pct.to_f, span].min
      ratio = (loss_pct / span.to_f)
      new_sl = max_loss + (ratio * (min_loss - max_loss)) # note min_loss < max_loss (negative direction)

      # Apply time-based tightening
      if seconds_below_entry.to_i > 0 && cfg2[:time_tighten_per_min]
        minutes = seconds_below_entry.to_f / 60.0
        new_sl -= (minutes * cfg2[:time_tighten_per_min].to_f) # subtract because we're tightening (reducing allowed loss)
      end

      # ATR penalties (volatility-based tightening)
      if cfg2[:atr_penalty_thresholds].is_a?(Array)
        cfg2[:atr_penalty_thresholds].each do |r|
          if atr_ratio.to_f <= r[:threshold].to_f
            new_sl -= r[:penalty_pct].to_f # subtract to tighten
            break
          end
        end
      end

      # Clamp to [min_loss, max_loss] range
      [[new_sl, min_loss].max, max_loss].min.round(4)
    end

    # Helper: Convert entry price and loss percent to SL price
    # For options, this is straightforward: entry_price * (1 - loss_pct/100)
    def sl_price_from_entry(entry_price, loss_pct)
      entry_price.to_f * (1.0 - (loss_pct.to_f.abs / 100.0))
    end
  end
end
