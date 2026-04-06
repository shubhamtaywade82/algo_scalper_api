# frozen_string_literal: true

# Ported from delta_exchange_bot Trading::Analysis::SmcConfluence::Engine (Pine parity).
# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/SpaceInsideArrayLiteralBrackets, Style/NegatedIf, Lint/AmbiguousOperatorPrecedence
module Smc
  module Confluence
    # Bar-by-bar replay of `smc_confluence.pine` signal logic (Pine v6).
    class Engine
      def self.run(candles, configuration: Configuration.new)
        new(candles, configuration).compute
      end

      def initialize(candles, configuration)
        @candles = candles
        @cfg = configuration
        @state = State.new
      end

      def compute
        return [] if @candles.empty?

        @candles.each_index.map { |i| step_bar(i) }
      end

      private

      attr_reader :state, :cfg, :candles

      def step_bar(i)
        swing = cfg.smc_swing
        s = state
        c = candles[i]
        high = c[:high].to_f
        low = c[:low].to_f
        open = c[:open].to_f
        close = c[:close].to_f
        prev_close = i.positive? ? candles[i - 1][:close].to_f : close
        prev_open = i.positive? ? candles[i - 1][:open].to_f : open

        update_atr(i, high, low, close)
        atr14 = s.atr_prev&.to_f

        update_calendar_and_sessions(i, high, low, close, c[:timestamp])

        # --- Layer 1A: SMC pivots (age then optional reset) ---
        s.ph_age += 1
        s.pl_age += 1
        if (ph_val = pivot_high_confirmed(i, swing))
          s.last_ph = ph_val
          s.last_ph_bar = i - swing
          s.ph_age = 0
        end
        if (pl_val = pivot_low_confirmed(i, swing))
          s.last_pl = pl_val
          s.last_pl_bar = i - swing
          s.pl_age = 0
        end

        ph_valid = !s.last_ph.nil? && s.ph_age <= cfg.ob_expire
        pl_valid = !s.last_pl.nil? && s.pl_age <= cfg.ob_expire

        bos_bull = ph_valid && close > s.last_ph && prev_close <= s.last_ph
        bos_bear = pl_valid && close < s.last_pl && prev_close >= s.last_pl
        choch_bull = ph_valid && close > s.last_ph && prev_close <= s.last_ph && s.structure_bias == -1
        choch_bear = pl_valid && close < s.last_pl && prev_close >= s.last_pl && s.structure_bias == 1

        if bos_bull || choch_bull
          s.structure_bias = 1
        elsif bos_bear || choch_bear
          s.structure_bias = -1
        end

        # --- Layer 1C: Order blocks ---
        s.bull_ob_age += 1
        s.bear_ob_age += 1
        impulse_body_pct = close.abs.positive? ? ((close - open).abs / close * 100.0) : 0.0
        if i.positive?
          if (bos_bull || choch_bull) && impulse_body_pct >= cfg.ob_body_pct && prev_close < prev_open
            prev = candles[i - 1]
            s.bull_ob_hi = prev[:high].to_f
            s.bull_ob_lo = prev[:low].to_f
            s.bull_ob_bar = i - 1
            s.bull_ob_age = 0
          end
          if (bos_bear || choch_bear) && impulse_body_pct >= cfg.ob_body_pct && prev_close > prev_open
            prev = candles[i - 1]
            s.bear_ob_hi = prev[:high].to_f
            s.bear_ob_lo = prev[:low].to_f
            s.bear_ob_bar = i - 1
            s.bear_ob_age = 0
          end
        end

        bull_ob_valid = !s.bull_ob_hi.nil? && s.bull_ob_age <= cfg.ob_expire && close >= s.bull_ob_lo * 0.998
        bear_ob_valid = !s.bear_ob_hi.nil? && s.bear_ob_age <= cfg.ob_expire && close <= s.bear_ob_hi * 1.002
        in_bull_ob = bull_ob_valid && low <= s.bull_ob_hi && high >= s.bull_ob_lo
        in_bear_ob = bear_ob_valid && high >= s.bear_ob_lo && low <= s.bear_ob_hi

        # --- Layer 1D: Liquidity (uses previous bar rolling swing) ---
        liq_hi, liq_lo = rolling_high_low(i, cfg.liq_lookback)
        liq_sweep_bull = s.prev_liq_lo &&
                         low < s.prev_liq_lo - (s.prev_liq_lo * (cfg.liq_wick_pct / 100.0)) &&
                         close > s.prev_liq_lo
        liq_sweep_bear = s.prev_liq_hi &&
                         high > s.prev_liq_hi + (s.prev_liq_hi * (cfg.liq_wick_pct / 100.0)) &&
                         close < s.prev_liq_hi
        s.last_bull_sweep_bar = i if liq_sweep_bull
        s.last_bear_sweep_bar = i if liq_sweep_bear
        recent_bull_sweep = (i - s.last_bull_sweep_bar) <= swing * 2
        recent_bear_sweep = (i - s.last_bear_sweep_bar) <= swing * 2

        # --- Layer 2: Market structure ---
        ms = cfg.ms_swing
        ms_ph = pivot_high_confirmed(i, ms)
        ms_pl = pivot_low_confirmed(i, ms)
        ms_hh = !ms_ph.nil? && !s.prev_ms_ph.nil? && ms_ph > s.prev_ms_ph
        ms_lh = !ms_ph.nil? && !s.prev_ms_ph.nil? && ms_ph < s.prev_ms_ph
        ms_hl = !ms_pl.nil? && !s.prev_ms_pl.nil? && ms_pl > s.prev_ms_pl
        ms_ll = !ms_pl.nil? && !s.prev_ms_pl.nil? && ms_pl < s.prev_ms_pl

        if !ms_ph.nil?
          s.prev_ms_ph = s.last_ms_ph_val
          s.last_ms_ph_val = ms_ph
          s.last_ms_ph_bar = i - ms
        end
        if !ms_pl.nil?
          s.prev_ms_pl = s.last_ms_pl_val
          s.last_ms_pl_val = ms_pl
          s.last_ms_pl_bar = i - ms
        end
        s.ms_trend = 1 if ms_hh || ms_hl
        s.ms_trend = -1 if ms_lh || ms_ll

        # --- Layer 3: Trendlines ---
        tl_len = cfg.tl_pivot_len
        tl_ph = pivot_high_confirmed(i, tl_len)
        tl_pl = pivot_low_confirmed(i, tl_len)
        if !tl_ph.nil?
          s.tl_ph2 = s.tl_ph1
          s.tl_ph2_bar = s.tl_ph1_bar
          s.tl_ph1 = tl_ph
          s.tl_ph1_bar = i - tl_len
          s.tl_bear_broken = false
          s.tl_bear_retested = false
          s.tl_bear_break_bar = -999
        end
        if !tl_pl.nil?
          s.tl_pl2 = s.tl_pl1
          s.tl_pl2_bar = s.tl_pl1_bar
          s.tl_pl1 = tl_pl
          s.tl_pl1_bar = i - tl_len
          s.tl_bull_broken = false
          s.tl_bull_retested = false
          s.tl_bull_break_bar = -999
        end

        tl_bear_slope = bear_trendline_slope(s)
        tl_bull_slope = bull_trendline_slope(s)
        tl_bear_val = tl_bear_slope && s.tl_ph1 ? s.tl_ph1 + tl_bear_slope * (i - s.tl_ph1_bar) : nil
        tl_bull_val = tl_bull_slope && s.tl_pl1 ? s.tl_pl1 + tl_bull_slope * (i - s.tl_pl1_bar) : nil

        prev_bear = s.prev_tl_bear_val
        prev_bull = s.prev_tl_bull_val
        tl_bear_break = tl_bear_val && prev_bear && close > tl_bear_val && prev_close <= prev_bear
        tl_bull_break = tl_bull_val && prev_bull && close < tl_bull_val && prev_close >= prev_bull

        if tl_bear_break
          s.tl_bear_broken = true
          s.tl_bear_retested = false
          s.tl_bear_break_bar = i
        end
        if tl_bull_break
          s.tl_bull_broken = true
          s.tl_bull_retested = false
          s.tl_bull_break_bar = i
        end

        tl_bear_retest = s.tl_bear_broken && !s.tl_bear_retested && tl_bear_val &&
                         (i - s.tl_bear_break_bar) > 1 &&
                         ((close - tl_bear_val).abs / close * 100.0) <= cfg.tl_retest_pct &&
                         close > tl_bear_val
        tl_bull_retest = s.tl_bull_broken && !s.tl_bull_retested && tl_bull_val &&
                         (i - s.tl_bull_break_bar) > 1 &&
                         ((close - tl_bull_val).abs / close * 100.0) <= cfg.tl_retest_pct &&
                         close < tl_bull_val
        s.tl_bear_retested = true if tl_bear_retest
        s.tl_bull_retested = true if tl_bull_retest

        # --- Layer 4: PDH/PDL proximity (pdh/pdl updated in update_calendar_and_sessions) ---
        pdh = s.pdh
        pdl = s.pdl
        pct = cfg.sess_liq_pct / 100.0
        pdh_sweep = !pdh.nil? && high > pdh * (1 + pct) && close < pdh
        pdl_sweep = !pdl.nil? && low < pdl * (1 - pct) && close > pdl
        near_pdh = !pdh.nil? && ((close - pdh).abs / close * 100.0) <= cfg.sess_liq_pct
        near_pdl = !pdl.nil? && ((close - pdl).abs / close * 100.0) <= cfg.sess_liq_pct
        near_sess_hi = near_session_level?(close, s.asia_hi) || near_session_level?(close, s.london_hi)
        near_sess_lo = near_session_level?(close, s.asia_lo) || near_session_level?(close, s.london_lo)
        sess_level_bull = near_pdl || near_sess_lo || pdl_sweep
        sess_level_bear = near_pdh || near_sess_hi || pdh_sweep

        # --- Layer 5: Volume profile ---
        poc, vah, val_line, vp_ok = volume_profile_levels(i)
        near_poc = vp_ok && !poc.nil? && ((close - poc).abs / close * 100.0) <= cfg.poc_zone_pct
        near_vah = vp_ok && !vah.nil? && ((close - vah).abs / close * 100.0) <= cfg.poc_zone_pct
        near_val = vp_ok && !val_line.nil? && ((close - val_line).abs / close * 100.0) <= cfg.poc_zone_pct
        vp_bull_conf = near_poc || near_val
        vp_bear_conf = near_poc || near_vah

        # --- Signal engine ---
        long_s1 = choch_bull ? 1 : 0
        long_s2 = in_bull_ob ? 1 : 0
        long_s3 = recent_bull_sweep ? 1 : 0
        long_s4 = vp_bull_conf ? 1 : 0
        long_s5 = sess_level_bull ? 1 : 0
        long_s6 = tl_bear_retest ? 1 : 0
        short_s1 = choch_bear ? 1 : 0
        short_s2 = in_bear_ob ? 1 : 0
        short_s3 = recent_bear_sweep ? 1 : 0
        short_s4 = vp_bear_conf ? 1 : 0
        short_s5 = sess_level_bear ? 1 : 0
        short_s6 = tl_bull_retest ? 1 : 0
        long_score = long_s1 + long_s2 + long_s3 + long_s4 + long_s5 + long_s6
        short_score = short_s1 + short_s2 + short_s3 + short_s4 + short_s5 + short_s6
        cooldown_ok = (i - s.last_sig_bar) >= cfg.sig_cooldown
        long_signal = long_s1 == 1 && long_score >= cfg.min_score && cooldown_ok
        short_signal = short_s1 == 1 && short_score >= cfg.min_score && cooldown_ok
        s.last_sig_bar = i if long_signal || short_signal

        # Persist for next bar
        s.prev_liq_lo = liq_lo
        s.prev_liq_hi = liq_hi
        s.prev_tl_bear_val = tl_bear_val
        s.prev_tl_bull_val = tl_bull_val

        BarResult.new(
          bar_index: i,
          bos_bull: bos_bull,
          bos_bear: bos_bear,
          choch_bull: choch_bull,
          choch_bear: choch_bear,
          structure_bias: s.structure_bias,
          in_bull_ob: in_bull_ob,
          in_bear_ob: in_bear_ob,
          bull_ob_valid: bull_ob_valid,
          bear_ob_valid: bear_ob_valid,
          recent_bull_sweep: recent_bull_sweep,
          recent_bear_sweep: recent_bear_sweep,
          liq_sweep_bull: liq_sweep_bull,
          liq_sweep_bear: liq_sweep_bear,
          ms_trend: s.ms_trend,
          tl_bear_break: tl_bear_break,
          tl_bull_break: tl_bull_break,
          tl_bear_retest: tl_bear_retest,
          tl_bull_retest: tl_bull_retest,
          sess_level_bull: sess_level_bull,
          sess_level_bear: sess_level_bear,
          vp_bull_conf: vp_bull_conf,
          vp_bear_conf: vp_bear_conf,
          near_poc: near_poc,
          near_vah: near_vah,
          near_val: near_val,
          long_score: long_score,
          short_score: short_score,
          long_signal: long_signal,
          short_signal: short_signal,
          pdh_sweep: pdh_sweep,
          pdl_sweep: pdl_sweep,
          pdh: pdh,
          pdl: pdl,
          poc: poc,
          vah: vah,
          val_line: val_line,
          atr14: atr14
        )
      end

      def near_session_level?(close, level)
        return false if level.nil?

        ((close - level).abs / close * 100.0) <= cfg.sess_liq_pct
      end

      def bear_trendline_slope(s)
        return nil if s.tl_ph1.nil? || s.tl_ph2.nil?
        return nil if s.tl_ph1_bar == s.tl_ph2_bar

        (s.tl_ph1 - s.tl_ph2).to_f / (s.tl_ph1_bar - s.tl_ph2_bar)
      end

      def bull_trendline_slope(s)
        return nil if s.tl_pl1.nil? || s.tl_pl2.nil?
        return nil if s.tl_pl1_bar == s.tl_pl2_bar

        (s.tl_pl1 - s.tl_pl2).to_f / (s.tl_pl1_bar - s.tl_pl2_bar)
      end

      def update_atr(i, high, low, close)
        s = state
        prev_close = i.positive? ? candles[i - 1][:close].to_f : close
        tr = if i.zero?
               high - low
             else
               [
                 high - low,
                 (high - prev_close).abs,
                 (low - prev_close).abs
               ].max
             end
        period = cfg.atr_period
        s.atr_prev = if i.zero?
                       tr
                     elsif s.atr_prev.nil?
                       tr
                     else
                       (s.atr_prev * (period - 1) + tr) / period
                     end
      end

      def update_calendar_and_sessions(i, high, low, close, timestamp)
        s = state
        ts = timestamp.to_i
        date = Time.zone.at(ts).utc.to_date

        if s.prev_calendar_date && date != s.prev_calendar_date
          s.pdh = s.day_high
          s.pdl = s.day_low
          s.day_high = high
          s.day_low = low
        elsif s.day_high.nil?
          s.day_high = high
          s.day_low = low
        else
          s.day_high = [ s.day_high, high ].max
          s.day_low = [ s.day_low, low ].min
        end
        s.prev_calendar_date = date

        hour = Time.zone.at(ts).utc.hour
        in_asia = (0...8).cover?(hour)
        in_london = (8...16).cover?(hour)
        in_ny = (13...21).cover?(hour)

        if in_asia
          s.asia_hi = s.asia_hi.nil? || !s.was_asia ? high : [ s.asia_hi, high ].max
          s.asia_lo = s.asia_lo.nil? || !s.was_asia ? low : [ s.asia_lo, low ].min
          s.was_asia = true
        elsif s.was_asia
          s.was_asia = false
        end

        if in_london
          s.london_hi = s.london_hi.nil? || !s.was_london ? high : [ s.london_hi, high ].max
          s.london_lo = s.london_lo.nil? || !s.was_london ? low : [ s.london_lo, low ].min
          s.was_london = true
        elsif s.was_london
          s.was_london = false
        end

        if in_ny
          s.ny_hi = s.ny_hi.nil? || !s.was_ny ? high : [ s.ny_hi, high ].max
          s.ny_lo = s.ny_lo.nil? || !s.was_ny ? low : [ s.ny_lo, low ].min
          s.was_ny = true
        elsif s.was_ny
          s.was_ny = false
        end
      end

      def rolling_high_low(i, lookback)
        from = [ 0, i - lookback + 1 ].max
        hi = (from..i).map { |j| candles[j][:high].to_f }.max
        lo = (from..i).map { |j| candles[j][:low].to_f }.min
        [ hi, lo ]
      end

      # Confirms a pivot on the current bar index; rules match swing fractal (Pine pivothigh/pivotlow).
      def pivot_high_confirmed(i, swing)
        return nil if i < swing * 2

        c_idx = i - swing
        return nil if c_idx < swing

        h_mid = candles[c_idx][:high].to_f
        left_ok = ((c_idx - swing)...c_idx).all? { |j| candles[j][:high].to_f < h_mid }
        right_ok = ((c_idx + 1)..i).all? { |j| candles[j][:high].to_f <= h_mid }
        left_ok && right_ok ? h_mid : nil
      end

      def pivot_low_confirmed(i, swing)
        return nil if i < swing * 2

        c_idx = i - swing
        return nil if c_idx < swing

        l_mid = candles[c_idx][:low].to_f
        left_ok = ((c_idx - swing)...c_idx).all? { |j| candles[j][:low].to_f > l_mid }
        right_ok = ((c_idx + 1)..i).all? { |j| candles[j][:low].to_f >= l_mid }
        left_ok && right_ok ? l_mid : nil
      end

      def volume_profile_levels(i)
        vp = cfg.vp_bars
        return [ nil, nil, nil, false ] if (i + 1) < vp

        from = i - vp + 1
        max_vol = 0.0
        max_vol_price = candles[i][:close].to_f
        vwap_sum = 0.0
        vol_total = 0.0
        vwsum2 = 0.0

        (from..i).each do |j|
          candle = candles[j]
          vol = volume_value(candle)
          tp = typical_price(candle)
          if vol > max_vol
            max_vol = vol
            max_vol_price = tp
          end
          vwap_sum += tp * vol
          vol_total += vol
          vwsum2 += tp * tp * vol
        end

        return [ nil, nil, nil, false ] if vol_total <= 0

        poc = max_vol_price
        vwap_val = vwap_sum / vol_total
        variance = (vwsum2 / vol_total) - (vwap_val * vwap_val)
        sigma = variance.positive? ? Math.sqrt(variance) : state.atr_prev.to_f
        vah = vwap_val + sigma
        val_line = vwap_val - sigma
        [ poc, vah, val_line, true ]
      end

      def typical_price(candle)
        (candle[:high].to_f + candle[:low].to_f + candle[:close].to_f) / 3.0
      end

      def volume_value(candle)
        v = candle[:volume]
        v.nil? ? 0.0 : v.to_f
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/SpaceInsideArrayLiteralBrackets, Style/NegatedIf, Lint/AmbiguousOperatorPrecedence
