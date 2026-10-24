# frozen_string_literal: true

module Research
  class OptionExpansionAnalyzer
    # Analyzes option premium metrics for a specific strike relative to a breakout opportunity.
    # @param option_candles [Array<Hash>] Daily option candles (already filtered/aligned)
    # @param underlying_candles [Array<Hash>] Daily NIFTY candles
    # @param trade_opp [Hash] The trade opportunity context from OpeningRangeAnalyzer
    # @param strike_label [String] e.g. "ATM", "ATM-1", "ATM+1"
    # @return [Hash] V3 Event-centric option metrics
    def self.analyze(option_candles, underlying_candles, trade_opp, strike_label = "ATM")
      entry_time = trade_opp[:entry_time]
      trade_opp[:entry_index]

      # Find entry index in option candles
      opt_entry_idx = option_candles.index { |c| c[:timestamp] >= entry_time }
      execution_idx = opt_entry_idx ? opt_entry_idx + 1 : nil
      execution_idx = option_candles.size - 1 if execution_idx && execution_idx >= option_candles.size

      if execution_idx.nil? || option_candles[execution_idx].nil?
        return {}
      end

      entry_candle = option_candles[execution_idx]
      entry_price = entry_candle[:open]

      # 1. Option Structure Features at entry time (no lookahead)
      first_15m_options = option_candles.first(15)
      prem_open = option_candles.first[:open]
      prem_high_15m = first_15m_options.pluck(:high).max || prem_open
      prem_low_15m = first_15m_options.pluck(:low).min || prem_open

      # Premium EMA5 at entry
      prem_series = CandleSeries.new(symbol: "PREM", interval: "1")
      option_candles.first(execution_idx).each do |c|
        prem_series.add_candle(Candle.new(
          timestamp: c[:timestamp], open: c[:open], high: c[:high], low: c[:low], close: c[:close], volume: c[:volume]
        ))
      end
      prem_ema5 = prem_series.ema(5)

      # 2. Future Premium Behavior (Trade Lifecycle)
      post_entry_options = option_candles[execution_idx..]

      peak_price = entry_price
      peak_time = entry_time
      peak_offset = 0

      # Time to thresholds
      time_to_20 = nil
      time_to_30 = nil
      time_to_50 = nil
      time_to_75 = nil
      time_to_100 = nil

      # Time above thresholds (counts minutes)
      time_above_20 = 0
      time_above_30 = 0
      time_above_50 = 0
      time_above_75 = 0
      time_above_100 = 0

      # Exhaustion tracking
      peak_exhaustion_score = 0
      exhaustion_time = nil
      divergence_detected = false

      post_entry_options.each_with_index do |c, idx|
        current_idx = execution_idx + idx

        # Track Peak
        if c[:high] > peak_price
          peak_price = c[:high]
          peak_time = c[:timestamp]
          peak_offset = idx
        end

        # Calculate returns
        high_ret = entry_price.positive? ? ((c[:high] - entry_price) / entry_price) * 100.0 : 0.0
        close_ret = entry_price.positive? ? ((c[:close] - entry_price) / entry_price) * 100.0 : 0.0

        # Time to Thresholds
        time_to_20 ||= idx if high_ret >= 20.0
        time_to_30 ||= idx if high_ret >= 30.0
        time_to_50 ||= idx if high_ret >= 50.0
        time_to_75 ||= idx if high_ret >= 75.0
        time_to_100 ||= idx if high_ret >= 100.0

        # Time Above Thresholds
        time_above_20 += 1 if close_ret >= 20.0
        time_above_30 += 1 if close_ret >= 30.0
        time_above_50 += 1 if close_ret >= 50.0
        time_above_75 += 1 if close_ret >= 75.0
        time_above_100 += 1 if close_ret >= 100.0

        # Calculate dynamic Premium Exhaustion Score (PES) at this minute
        pes, div = calculate_pes(current_idx, option_candles, underlying_candles, trade_opp[:breakout_type], entry_price, peak_price)
        divergence_detected ||= div
        if pes > peak_exhaustion_score
          peak_exhaustion_score = pes
          exhaustion_time = c[:timestamp] if pes >= 75 && exhaustion_time.nil?
        end
      end

      # MFE & MAE
      mfe_pct = entry_price.positive? ? ((peak_price - entry_price) / entry_price) * 100.0 : 0.0
      lowest_post_entry = post_entry_options.pluck(:low).min || entry_price
      mae_pct = entry_price.positive? ? ((lowest_post_entry - entry_price) / entry_price) * 100.0 : 0.0

      time_to_peak = ((peak_time - entry_time) / 60).round

      # Calculate Multi-Horizon Option MFE % (no lookahead)
      horizons = {}
      [5, 10, 15, 30, 60].each do |h_mins|
        segment = post_entry_options.first(h_mins)
        peak_seg = segment.any? ? segment.map { |c| c[:high] }.max : entry_price
        horizons[:"mfe_#{h_mins}m"] = (entry_price.positive? ? ((peak_seg - entry_price) / entry_price) * 100.0 : 0.0).round(2)
      end

      # Decay after peak
      subsequent_lowest = post_entry_options[peak_offset..].pluck(:low).min || peak_price
      drawdown_pct = peak_price.positive? ? ((peak_price - subsequent_lowest) / peak_price) * 100.0 : 0.0

      # Velocity & Gamma Efficiency
      velocity = time_to_peak.positive? ? (mfe_pct / time_to_peak) : mfe_pct

      und_max_cont = trade_opp[:max_continuation]
      gamma_efficiency = und_max_cont.positive? ? (mfe_pct / und_max_cont) : 0.0

      und_entry_price = trade_opp[:underlying_entry_price]
      und_max_cont_pct = und_entry_price.positive? ? (und_max_cont / und_entry_price) * 100.0 : 0.0
      trade_elasticity = und_max_cont_pct.positive? ? (mfe_pct / und_max_cont_pct) : 0.0

      # Expansion Quality Score (EQS)
      eqs = compute_eqs(velocity, gamma_efficiency, drawdown_pct, trade_opp[:sustained])

      # Extract first 15m option candles (09:15 to 09:30 IST) to classify shape taxonomy
      first_15m_options = option_candles.first(15)
      f_open = first_15m_options.any? ? first_15m_options.first[:open].to_f : 0.0
      f_high = first_15m_options.any? ? (first_15m_options.map { |c| c[:high].to_f }.max || f_open) : 0.0
      f_low = first_15m_options.any? ? (first_15m_options.map { |c| c[:low].to_f }.min || f_open) : 0.0
      f_mfe = f_open.positive? ? ((f_high - f_open) / f_open) * 100.0 : 0.0
      f_mae = f_open.positive? ? ((f_low - f_open) / f_open) * 100.0 : 0.0
      premium_pattern = Research::PremiumTaxonomyClassifier.classify(first_15m_options, f_mfe, f_mae)

      {
        strike_label: strike_label,
        premium_pattern: premium_pattern,
        horizons: horizons,
        entry_price: entry_price.round(2),
        peak_price: peak_price.round(2),
        peak_time: peak_time,
        mfe_pct: mfe_pct.round(2),
        mae_pct: mae_pct.round(2),
        time_to_peak_minutes: time_to_peak,
        drawdown_from_peak_pct: drawdown_pct.round(2),
        velocity_pct_per_min: velocity.round(3),
        trade_elasticity: trade_elasticity.round(3),
        gamma_efficiency: gamma_efficiency.round(3),
        expansion_quality_score: eqs,
        thresholds: {
          time_to_20: time_to_20,
          time_to_30: time_to_30,
          time_to_50: time_to_50,
          time_to_75: time_to_75,
          time_to_100: time_to_100,
          time_above_20: time_above_20,
          time_above_30: time_above_30,
          time_above_50: time_above_50,
          time_above_75: time_above_75,
          time_above_100: time_above_100
        },
        exhaustion: {
          peak_exhaustion_score: peak_exhaustion_score,
          exhaustion_time: exhaustion_time,
          divergence_detected: divergence_detected
        },
        premium_features: {
          premium_open: prem_open.round(2),
          premium_high_15m: prem_high_15m.round(2),
          premium_low_15m: prem_low_15m.round(2),
          premium_ema5_at_entry: prem_ema5&.round(2),
          premium_volume_at_entry: entry_candle[:volume]
        }
      }
    end

    def self.calculate_pes(idx, active_candles, underlying_candles, breakout_type, entry_price, peak_price)
      close = active_candles[idx][:close]

      pullback = peak_price.positive? ? ((peak_price - close) / peak_price) * 100.0 : 0.0

      v_1m = active_candles[idx][:close] - active_candles[idx - 1][:close]
      v_3m = idx >= 3 ? (active_candles[idx][:close] - active_candles[idx - 3][:close]) : 0.0

      v_prev = active_candles[idx - 1][:close] - active_candles[idx - 2][:close]
      acceleration = v_1m - v_prev

      peak_candle_idx = active_candles[0..idx].each_with_index.max_by { |c, _| c[:high] }[1]
      time_since_high = idx - peak_candle_idx

      divergence = false
      if idx >= 3
        und_prev_3 = underlying_candles[(idx - 3)...idx]
        und_curr = underlying_candles[idx]

        und_extreme = false
        if breakout_type == :bullish
          und_extreme = und_curr && und_prev_3.all? && und_curr[:high] > und_prev_3.pluck(:high).max
        else
          und_extreme = und_curr && und_prev_3.all? && und_curr[:low] < und_prev_3.pluck(:low).min
        end

        opt_prev_3 = active_candles[(idx - 3)...idx]
        opt_failed = active_candles[idx][:high] <= opt_prev_3.pluck(:high).max
        divergence = und_extreme && opt_failed
      end

      score = 0
      score += 25 if pullback >= 10.0
      score += 20 if acceleration.negative?
      score += 20 if time_since_high >= 3
      score += 25 if divergence
      score += 10 if v_3m.negative?

      [[score, 100].min, divergence]
    end

    def self.compute_eqs(velocity, gamma_efficiency, drawdown, sustained)
      vel_score = [velocity * 6.0, 30.0].min
      gamma_score = [gamma_efficiency * 12.0, 25.0].min
      drawdown_score = [25.0 - (drawdown * 0.5), 0.0].max
      alignment_score = sustained ? 20.0 : 0.0

      (vel_score + gamma_score + drawdown_score + alignment_score).round
    end
  end
end
