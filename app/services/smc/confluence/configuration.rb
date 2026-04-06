# frozen_string_literal: true

module Smc
  module Confluence
    # Defaults match Pine `smc_confluence.pine` inputs.
    # Pivot lengths are ENV-overridable for parity with MS swing in other SMC modules.
    class Configuration
      attr_reader :smc_swing, :ob_body_pct, :ob_expire, :liq_lookback, :liq_wick_pct,
                  :ms_swing, :tl_pivot_len, :tl_retest_pct, :vp_bars, :vp_rows,
                  :poc_zone_pct, :sess_liq_pct, :min_score, :sig_cooldown, :atr_period

      def initialize(
        smc_swing: Integer(ENV.fetch('ANALYSIS_SMC_SWING', '10')),
        ob_body_pct: 0.3,
        ob_expire: 50,
        liq_lookback: Integer(ENV.fetch('ANALYSIS_LIQ_LOOKBACK', '20')),
        liq_wick_pct: 0.1,
        ms_swing: Integer(ENV.fetch('ANALYSIS_MS_SWING', '10')),
        tl_pivot_len: Integer(ENV.fetch('ANALYSIS_TL_PIVOT_LEN', '10')),
        tl_retest_pct: 0.15,
        vp_bars: 100,
        vp_rows: 24,
        poc_zone_pct: 0.2,
        sess_liq_pct: 0.1,
        min_score: 3,
        sig_cooldown: 5,
        atr_period: 14
      )
        @smc_swing = Integer(smc_swing)
        @ob_body_pct = Float(ob_body_pct)
        @ob_expire = Integer(ob_expire)
        @liq_lookback = Integer(liq_lookback)
        @liq_wick_pct = Float(liq_wick_pct)
        @ms_swing = Integer(ms_swing)
        @tl_pivot_len = Integer(tl_pivot_len)
        @tl_retest_pct = Float(tl_retest_pct)
        @vp_bars = Integer(vp_bars)
        @vp_rows = Integer(vp_rows)
        @poc_zone_pct = Float(poc_zone_pct)
        @sess_liq_pct = Float(sess_liq_pct)
        @min_score = Integer(min_score)
        @sig_cooldown = Integer(sig_cooldown)
        @atr_period = Integer(atr_period)
      end
    end
  end
end
