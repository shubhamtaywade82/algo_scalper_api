# frozen_string_literal: true

module Research
  class ExitCaptureAnalyzer
    STRATEGY_METHODS = {
      fixed_30: :simulate_fixed_target_30,
      fixed_50: :simulate_fixed_target_50,
      trail_20: :simulate_trailing_stop_20,
      und_ema9: :simulate_underlying_ema9,
      prem_ema5: :simulate_premium_ema5,
      momentum_decay: :simulate_momentum_decay,
      hybrid_divergence: :simulate_hybrid_divergence,
      hold_to_close: :simulate_hold_to_close,
      mfe_retrace_25: :simulate_mfe_retrace_25,
      mfe_retrace_35: :simulate_mfe_retrace_35,
      mfe_retrace_50: :simulate_mfe_retrace_50,
      gamma_state: :simulate_gamma_state,
      velocity_ratchet: :simulate_velocity_ratchet
    }.freeze
    STRATEGY_NAMES = STRATEGY_METHODS.keys.freeze

    # Simulates various exit candidates and measures their capture efficiency on a specific strike.
    # @param underlying_candles [Array<Hash>] Daily NIFTY candles
    # @param option_candles [Array<Hash>] Daily option candles for a specific strike
    # @param trade_opp [Hash] Result from OpeningRangeAnalyzer for the breakout opportunity
    # @param expansion_context [Hash] Result from OptionExpansionAnalyzer for this strike
    # @return [Hash] Simulation results for each exit candidate
    def self.run(underlying_candles, option_candles, trade_opp, expansion_context)
      breakout_type = trade_opp[:breakout_type]
      entry_time = trade_opp[:entry_time]

      # Find entry index in option candles
      opt_idx = option_candles.index { |c| c[:timestamp] >= entry_time } || trade_opp[:entry_index]
      entry_idx = opt_idx + 1
      entry_idx = option_candles.size - 1 if entry_idx >= option_candles.size

      entry_price = expansion_context[:entry_price]
      peak_price = expansion_context[:peak_price]

      rules = STRATEGY_METHODS.transform_values { |m| method(m) }

      results = {}
      rules.each do |name, sim_method|
        exit_price, exit_time, exit_reason = sim_method.call(
          entry_price, entry_idx, option_candles, underlying_candles, breakout_type
        )

        hold_time = ((exit_time - entry_time) / 60).round

        # Capture efficiency / Opportunity Retention: (exit - entry) / (peak - entry)
        efficiency = 0.0
        denom = peak_price - entry_price
        if denom.positive?
          efficiency = (exit_price - entry_price) / denom
        end

        lost_profit_pts = peak_price - exit_price
        giveback = peak_price.positive? ? ((peak_price - exit_price) / peak_price) * 100.0 : 0.0
        return_pct = entry_price.positive? ? ((exit_price - entry_price) / entry_price) * 100.0 : 0.0

        peak_time = expansion_context[:peak_time]
        leakage_time = peak_time && exit_time > peak_time ? ((exit_time - peak_time) / 60).round : 0
        leakage_speed = leakage_time.positive? ? (lost_profit_pts / leakage_time) : 0.0

        results[name] = {
          exit_price: exit_price.round(2),
          exit_time: exit_time,
          exit_reason: exit_reason,
          holding_time_minutes: hold_time,
          capture_efficiency: efficiency.round(4),
          opportunity_retention_ratio: [efficiency, 0.0].max.round(4),
          lost_profit_points: lost_profit_pts.round(2),
          leakage_time: leakage_time,
          leakage_speed: leakage_speed.round(4),
          giveback_pct: giveback.round(2),
          return_pct: return_pct.round(2),
          win: return_pct > 0.0
        }
      end

      results
    end

    # 1. Exit A: Fixed target of +30%
    def self.simulate_fixed_target_30(entry_price, entry_idx, active_candles, *, **)
      target = entry_price * 1.30
      active_candles[entry_idx..].each do |c|
        if c[:high] >= target
          return [target, c[:timestamp], "target_hit"]
        end
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 2. Exit B: Fixed target of +50%
    def self.simulate_fixed_target_50(entry_price, entry_idx, active_candles, *, **)
      target = entry_price * 1.50
      active_candles[entry_idx..].each do |c|
        if c[:high] >= target
          return [target, c[:timestamp], "target_hit"]
        end
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 3. Exit C: Trailing stop of 20%
    def self.simulate_trailing_stop_20(entry_price, entry_idx, active_candles, *, **)
      current_peak = entry_price
      active_candles[entry_idx..].each do |c|
        current_peak = [current_peak, c[:high]].max
        stop_level = current_peak * 0.80
        if c[:low] <= stop_level
          return [stop_level, c[:timestamp], "trailing_stop"]
        end
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 4. Exit D: Underlying loses EMA9
    def self.simulate_underlying_ema9(entry_price, entry_idx, active_candles, underlying_candles, breakout_type)
      und_series = CandleSeries.new(symbol: "NIFTY", interval: "1")

      underlying_candles.first(entry_idx).each do |c|
        und_series.add_candle(Candle.new(
          timestamp: c[:timestamp], open: c[:open], high: c[:high], low: c[:low], close: c[:close], volume: c[:volume]
        ))
      end

      active_candles[entry_idx..].each_with_index do |c, offset|
        idx = entry_idx + offset
        und_c = underlying_candles[idx]
        break if und_c.nil?

        und_series.add_candle(Candle.new(
          timestamp: und_c[:timestamp], open: und_c[:open], high: und_c[:high], low: und_c[:low], close: und_c[:close], volume: und_c[:volume]
        ))

        ema9 = und_series.ema(9)
        if ema9
          if breakout_type == :bullish && und_c[:close] < ema9
            return [c[:close], c[:timestamp], "underlying_lost_ema9"]
          elsif breakout_type == :bearish && und_c[:close] > ema9
            return [c[:close], c[:timestamp], "underlying_lost_ema9"]
          end
        end
      end

      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 5. Exit E: Premium loses EMA5
    def self.simulate_premium_ema5(entry_price, entry_idx, active_candles, *, **)
      prem_series = CandleSeries.new(symbol: "PREM", interval: "1")

      active_candles.first(entry_idx).each do |c|
        prem_series.add_candle(Candle.new(
          timestamp: c[:timestamp], open: c[:open], high: c[:high], low: c[:low], close: c[:close], volume: c[:volume]
        ))
      end

      active_candles[entry_idx..].each do |c|
        prem_series.add_candle(Candle.new(
          timestamp: c[:timestamp], open: c[:open], high: c[:high], low: c[:low], close: c[:close], volume: c[:volume]
        ))

        ema5 = prem_series.ema(5)
        if ema5 && c[:close] < ema5
          return [c[:close], c[:timestamp], "premium_lost_ema5"]
        end
      end

      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 6. Exit F: Premium momentum decay (low of previous 2 lows, or no new high for 3 mins)
    def self.simulate_momentum_decay(entry_price, entry_idx, active_candles, *, **)
      recent_highs = []

      active_candles[entry_idx..].each_with_index do |c, offset|
        idx = entry_idx + offset

        # Check low of last 2 candles
        if offset >= 2
          prev_low = [active_candles[idx - 1][:low], active_candles[idx - 2][:low]].min
          if c[:close] < prev_low
            return [c[:close], c[:timestamp], "low_of_previous_2_broken"]
          end
        end

        # Check no new high for 3 minutes
        recent_highs << c[:high]
        recent_highs.shift if recent_highs.size > 3
        if recent_highs.size == 3 && recent_highs.all? { |h| h <= recent_highs.first } && offset >= 3
          return [c[:close], c[:timestamp], "no_new_high_3_min"]
        end
      end

      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 7. Exit G: Hybrid Divergence exit
    def self.simulate_hybrid_divergence(entry_price, entry_idx, active_candles, underlying_candles, breakout_type)
      active_candles[entry_idx..].each_with_index do |c, offset|
        idx = entry_idx + offset
        next if offset < 3

        und_prev_3 = underlying_candles[(idx - 3)...idx]
        und_curr = underlying_candles[idx]
        break if und_curr.nil? || und_prev_3.any?(&:nil?)

        und_extreme = false
        if breakout_type == :bullish
          und_extreme = und_curr[:high] > und_prev_3.map { |x| x[:high] }.max
        else
          und_extreme = und_curr[:low] < und_prev_3.map { |x| x[:low] }.min
        end

        opt_prev_3 = active_candles[(idx - 3)...idx]
        opt_curr = active_candles[idx]
        opt_failed = opt_curr[:high] <= opt_prev_3.map { |x| x[:high] }.max

        if und_extreme && opt_failed
          return [c[:close], c[:timestamp], "bearish_divergence"]
        end
      end

      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 8. Hold to close
    def self.simulate_hold_to_close(entry_price, entry_idx, active_candles, *, **)
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 9-11. MFE retrace exits — mirror of live Orders::MfeExitEngine:
    # stop = peak - ratio * (peak - entry), active once MFE > 0.
    def self.simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio:)
      peak = entry_price
      active_candles[entry_idx..].each do |c|
        peak = [peak, c[:high]].max
        mfe = peak - entry_price
        next unless mfe.positive?

        stop = peak - (mfe * ratio)
        return [stop, c[:timestamp], "mfe_retrace"] if c[:low] <= stop
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    def self.simulate_mfe_retrace_25(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.25)
    end

    def self.simulate_mfe_retrace_35(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.35)
    end

    def self.simulate_mfe_retrace_50(entry_price, entry_idx, active_candles, *, **)
      simulate_mfe_retrace(entry_price, entry_idx, active_candles, ratio: 0.50)
    end

    # 12. Gamma-state exit — mirror of live Orders::GammaTrailingEngine (NIFTY config).
    # 4 states from profit/velocity/acceleration; exit when candle low touches the state's stop.
    GAMMA_STATE_CFG = {
      gamma_trigger: 0.25, velocity_threshold: 0.05,
      gamma_trail: 0.65, normal_trail: 0.80, exhaust_trail: 0.90,
      survival_sl: 0.88, survival_profit: 0.10
    }.freeze

    def self.simulate_gamma_state(entry_price, entry_idx, active_candles, *, **)
      cfg = GAMMA_STATE_CFG
      peak = entry_price
      # rubocop:disable Rails/Pluck -- array of hashes, not AR relation; pluck won't work
      closes = active_candles.first(entry_idx).map { |c| c[:close] }
      # rubocop:enable Rails/Pluck

      active_candles[entry_idx..].each do |c|
        closes << c[:close]
        peak = [peak, c[:high]].max

        profit = (c[:close] - entry_price) / entry_price
        velocity = closes.size >= 2 ? (closes[-1] - closes[-2]) / closes[-2] : 0.0
        acceleration =
          if closes.size >= 3
            v1 = (closes[-2] - closes[-3]) / closes[-3]
            (velocity - v1)
          else
            0.0
          end

        stop =
          if profit < cfg[:survival_profit]
            entry_price * cfg[:survival_sl]
          elsif profit > cfg[:gamma_trigger] && acceleration.positive?
            peak * cfg[:gamma_trail]
          elsif velocity < cfg[:velocity_threshold]
            peak * cfg[:exhaust_trail]
          else
            peak * cfg[:normal_trail]
          end

        return [stop, c[:timestamp], "gamma_state_stop"] if c[:low] <= stop
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end

    # 13. Velocity ratchet — peak-capture exit designed from V4/V5 findings:
    # premium peaked on every trade then gave back 28-99%; this floors the giveback.
    # Arms at MFE >= 10% of entry. Floor = max(entry*1.02, peak - gap);
    # gap = 35% of MFE while 1-min velocity > 0, tightens to 15% once velocity <= 0.
    # Floor only ever rises. Hard exit: velocity < 0 for 3 consecutive minutes AND close < EMA5.
    def self.simulate_velocity_ratchet(entry_price, entry_idx, active_candles, *, **)
      arm_threshold = entry_price * 1.10
      peak = entry_price
      floor = nil
      neg_velocity_run = 0
      # rubocop:disable Rails/Pluck -- array of hashes, not AR relation; pluck won't work
      closes = active_candles.first(entry_idx).map { |c| c[:close] }
      # rubocop:enable Rails/Pluck

      active_candles[entry_idx..].each do |c|
        closes << c[:close]
        peak = [peak, c[:high]].max

        velocity = closes.size >= 2 ? closes[-1] - closes[-2] : 0.0
        neg_velocity_run = velocity.negative? ? neg_velocity_run + 1 : 0

        if peak >= arm_threshold
          mfe = peak - entry_price
          gap_ratio = velocity.positive? ? 0.35 : 0.15
          candidate = [entry_price * 1.02, peak - (mfe * gap_ratio)].max
          floor = floor.nil? ? candidate : [floor, candidate].max
        end

        next unless floor
        return [floor, c[:timestamp], "ratchet_floor"] if c[:low] <= floor

        if neg_velocity_run >= 3 && closes.size >= 5
          ema5 = closes.last(5).sum / 5.0
          return [c[:close], c[:timestamp], "velocity_hard_exit"] if c[:close] < ema5
        end
      end
      c_last = active_candles.last
      [c_last[:close], c_last[:timestamp], "market_close"]
    end
  end
end
