# frozen_string_literal: true

module Smc
  module Confluence
    # Mutable bar-to-bar state mirroring Pine `var` fields.
    class State
      attr_accessor :structure_bias, :last_ph, :last_pl, :last_ph_bar, :last_pl_bar,
                    :ph_age, :pl_age,
                    :bull_ob_hi, :bull_ob_lo, :bull_ob_bar, :bull_ob_age,
                    :bear_ob_hi, :bear_ob_lo, :bear_ob_bar, :bear_ob_age,
                    :last_bull_sweep_bar, :last_bear_sweep_bar,
                    :prev_ms_ph, :prev_ms_pl, :last_ms_ph_val, :last_ms_pl_val,
                    :last_ms_ph_bar, :last_ms_pl_bar, :ms_trend,
                    :tl_ph1, :tl_ph1_bar, :tl_ph2, :tl_ph2_bar,
                    :tl_pl1, :tl_pl1_bar, :tl_pl2, :tl_pl2_bar,
                    :tl_bear_broken, :tl_bear_retested, :tl_bear_break_bar,
                    :tl_bull_broken, :tl_bull_retested, :tl_bull_break_bar,
                    :day_high, :day_low, :pdh, :pdl,
                    :asia_hi, :asia_lo, :london_hi, :london_lo, :ny_hi, :ny_lo,
                    :was_asia, :was_london, :was_ny,
                    :last_sig_bar, :prev_calendar_date,
                    :prev_liq_lo, :prev_liq_hi,
                    :prev_tl_bear_val, :prev_tl_bull_val,
                    :atr_prev

      def initialize
        reset_initial
      end

      def reset_initial
        @structure_bias = 0
        @last_ph = nil
        @last_pl = nil
        @last_ph_bar = -999
        @last_pl_bar = -999
        @ph_age = 0
        @pl_age = 0
        @bull_ob_hi = nil
        @bull_ob_lo = nil
        @bull_ob_bar = -999
        @bull_ob_age = 0
        @bear_ob_hi = nil
        @bear_ob_lo = nil
        @bear_ob_bar = -999
        @bear_ob_age = 0
        @last_bull_sweep_bar = -999
        @last_bear_sweep_bar = -999
        @prev_ms_ph = nil
        @prev_ms_pl = nil
        @last_ms_ph_val = nil
        @last_ms_pl_val = nil
        @last_ms_ph_bar = -999
        @last_ms_pl_bar = -999
        @ms_trend = 0
        @tl_ph1 = nil
        @tl_ph1_bar = -999
        @tl_ph2 = nil
        @tl_ph2_bar = -999
        @tl_pl1 = nil
        @tl_pl1_bar = -999
        @tl_pl2 = nil
        @tl_pl2_bar = -999
        @tl_bear_broken = false
        @tl_bear_retested = false
        @tl_bear_break_bar = -999
        @tl_bull_broken = false
        @tl_bull_retested = false
        @tl_bull_break_bar = -999
        @day_high = nil
        @day_low = nil
        @pdh = nil
        @pdl = nil
        @asia_hi = nil
        @asia_lo = nil
        @london_hi = nil
        @london_lo = nil
        @ny_hi = nil
        @ny_lo = nil
        @was_asia = false
        @was_london = false
        @was_ny = false
        @last_sig_bar = -999
        @prev_calendar_date = nil
        @prev_liq_lo = nil
        @prev_liq_hi = nil
        @prev_tl_bear_val = nil
        @prev_tl_bull_val = nil
        @atr_prev = nil
      end
    end
  end
end
