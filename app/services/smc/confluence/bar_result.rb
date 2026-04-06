# frozen_string_literal: true

module Smc
  module Confluence
    class BarResult
      attr_reader :bar_index,
                  :bos_bull, :bos_bear, :choch_bull, :choch_bear, :structure_bias,
                  :in_bull_ob, :in_bear_ob, :bull_ob_valid, :bear_ob_valid,
                  :recent_bull_sweep, :recent_bear_sweep,
                  :liq_sweep_bull, :liq_sweep_bear,
                  :ms_trend,
                  :tl_bear_break, :tl_bull_break, :tl_bear_retest, :tl_bull_retest,
                  :sess_level_bull, :sess_level_bear,
                  :vp_bull_conf, :vp_bear_conf, :near_poc, :near_vah, :near_val,
                  :long_score, :short_score, :long_signal, :short_signal,
                  :pdh_sweep, :pdl_sweep,
                  :pdh, :pdl, :poc, :vah, :val_line, :atr14

      def initialize(**attrs)
        @bar_index = attrs[:bar_index]
        @bos_bull = attrs[:bos_bull]
        @bos_bear = attrs[:bos_bear]
        @choch_bull = attrs[:choch_bull]
        @choch_bear = attrs[:choch_bear]
        @structure_bias = attrs[:structure_bias]
        @in_bull_ob = attrs[:in_bull_ob]
        @in_bear_ob = attrs[:in_bear_ob]
        @bull_ob_valid = attrs[:bull_ob_valid]
        @bear_ob_valid = attrs[:bear_ob_valid]
        @recent_bull_sweep = attrs[:recent_bull_sweep]
        @recent_bear_sweep = attrs[:recent_bear_sweep]
        @liq_sweep_bull = attrs[:liq_sweep_bull]
        @liq_sweep_bear = attrs[:liq_sweep_bear]
        @ms_trend = attrs[:ms_trend]
        @tl_bear_break = attrs[:tl_bear_break]
        @tl_bull_break = attrs[:tl_bull_break]
        @tl_bear_retest = attrs[:tl_bear_retest]
        @tl_bull_retest = attrs[:tl_bull_retest]
        @sess_level_bull = attrs[:sess_level_bull]
        @sess_level_bear = attrs[:sess_level_bear]
        @vp_bull_conf = attrs[:vp_bull_conf]
        @vp_bear_conf = attrs[:vp_bear_conf]
        @near_poc = attrs[:near_poc]
        @near_vah = attrs[:near_vah]
        @near_val = attrs[:near_val]
        @long_score = attrs[:long_score]
        @short_score = attrs[:short_score]
        @long_signal = attrs[:long_signal]
        @short_signal = attrs[:short_signal]
        @pdh_sweep = attrs[:pdh_sweep]
        @pdl_sweep = attrs[:pdl_sweep]
        @pdh = attrs[:pdh]
        @pdl = attrs[:pdl]
        @poc = attrs[:poc]
        @vah = attrs[:vah]
        @val_line = attrs[:val_line]
        @atr14 = attrs[:atr14]
      end

      def serialize
        {
          'bar_index' => bar_index,
          'bos_bull' => bos_bull,
          'bos_bear' => bos_bear,
          'choch_bull' => choch_bull,
          'choch_bear' => choch_bear,
          'structure_bias' => structure_bias,
          'in_bull_ob' => in_bull_ob,
          'in_bear_ob' => in_bear_ob,
          'bull_ob_valid' => bull_ob_valid,
          'bear_ob_valid' => bear_ob_valid,
          'recent_bull_sweep' => recent_bull_sweep,
          'recent_bear_sweep' => recent_bear_sweep,
          'liq_sweep_bull' => liq_sweep_bull,
          'liq_sweep_bear' => liq_sweep_bear,
          'ms_trend' => ms_trend,
          'tl_bear_break' => tl_bear_break,
          'tl_bull_break' => tl_bull_break,
          'tl_bear_retest' => tl_bear_retest,
          'tl_bull_retest' => tl_bull_retest,
          'sess_level_bull' => sess_level_bull,
          'sess_level_bear' => sess_level_bear,
          'vp_bull_conf' => vp_bull_conf,
          'vp_bear_conf' => vp_bear_conf,
          'near_poc' => near_poc,
          'near_vah' => near_vah,
          'near_val' => near_val,
          'long_score' => long_score,
          'short_score' => short_score,
          'long_signal' => long_signal,
          'short_signal' => short_signal,
          'pdh_sweep' => pdh_sweep,
          'pdl_sweep' => pdl_sweep,
          'pdh' => pdh,
          'pdl' => pdl,
          'poc' => poc,
          'vah' => vah,
          'val' => val_line,
          'atr14' => atr14
        }
      end
    end
  end
end
