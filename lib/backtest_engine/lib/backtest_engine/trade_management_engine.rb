# frozen_string_literal: true

module BacktestEngine
  class TradeManagementEngine
    attr_reader :position, :mfe, :mae, :trailing_sl

    def initialize(position, indicator_series:, option_data:, execution_engine:)
      @position = position
      @indicator_series = indicator_series
      @option_data = option_data
      @execution_engine = execution_engine

      @entry_price = position[:entry_price].to_f
      @mfe = @entry_price
      @mae = @entry_price

      # Option candle series for option-specific calculations
      @option_series = nil
      setup_option_series

      # Current stop-loss level (absolute price)
      sl_pct = position[:sl_pct] || 30.0
      @initial_sl = @entry_price * (1.0 - (sl_pct / 100.0))
      @trailing_sl = nil
    end

    def evaluate(candle_index, index_candle, option_price, timestamp)
      return nil unless option_price

      # 1. Update excursions (MFE / MAE)
      update_excursions(option_price)

      # 2. Check hard stop-loss
      current_sl = @trailing_sl || @initial_sl
      if option_price <= current_sl
        return { action: :exit, reason: @trailing_sl ? "TRAILING_STOP_LOSS" : "HARD_STOP_LOSS", price: current_sl }
      end

      # 3. Check hard target
      target_pct = @position[:target_pct] || 60.0
      target_price = @entry_price * (1.0 + (target_pct / 100.0))
      if option_price >= target_price
        return { action: :exit, reason: "TARGET_HIT", price: target_price }
      end

      # 4. Check Breakeven Trigger
      if @position[:breakeven_trigger]
        pnl_pct = ((option_price - @entry_price) / @entry_price) * 100.0
        if pnl_pct >= @position[:breakeven_trigger].to_f
          @trailing_sl = @trailing_sl ? [@trailing_sl, @entry_price].max : @entry_price
        end
      end

      # 5. Check Dynamic Trailing Stop-Loss
      if @position[:trail] || @position[:trail_type]
        pnl_pct = ((option_price - @entry_price) / @entry_price) * 100.0
        trail_trigger = @position[:trail_trigger] || 0.0

        if pnl_pct >= trail_trigger.to_f
          computed_sl = compute_trailing_stop(candle_index, index_candle, option_price, timestamp)
          if computed_sl
            @trailing_sl = @trailing_sl ? [@trailing_sl, computed_sl].max : computed_sl
          end
        end
      end

      # 6. Check Time Stop
      if @position[:max_hold_minutes]
        held_mins = ((timestamp - @position[:entry_time]) / 60.0).to_i
        if held_mins >= @position[:max_hold_minutes].to_i
          return { action: :exit, reason: "TIME_STOP", price: option_price }
        end
      end

      # 7. Check Underlying Regime / Trend Exit
      if check_underlying_exit?(candle_index, index_candle)
        return { action: :exit, reason: "UNDERLYING_REGIME_FLIP", price: option_price }
      end

      nil
    end

    def exit_metrics(exit_price, total_trend_points = 0.0, trend_captured_points = 0.0)
      denom = @mfe - @entry_price
      exit_efficiency = denom.zero? ? 100.0 : ((exit_price - @entry_price) / denom) * 100.0
      exit_efficiency = exit_efficiency.clamp(0.0, 100.0)

      trend_capture_pct = total_trend_points.zero? ? 0.0 : (trend_captured_points / total_trend_points) * 100.0

      {
        mfe: @mfe,
        mae: @mae,
        exit_efficiency: exit_efficiency,
        trend_capture_pct: trend_capture_pct
      }
    end

    private

    def setup_option_series
      strike_key = @position[:strike]
      option_type = @position[:option_type]
      raw_candles = @option_data[[strike_key, option_type]]
      return unless raw_candles&.any?

      candles = Market::Candle.build_series(raw_candles)
      @option_series = Market::CandleSeries.new(candles)
    rescue StandardError
      @option_series = nil
    end

    def update_excursions(ltp)
      @mfe = [@mfe, ltp].max
      @mae = [@mae, ltp].min
      @position[:highest_price] = @mfe
      @position[:lowest_price] = @mae
    end

    def compute_trailing_stop(candle_index, index_candle, option_price, timestamp)
      trail_type = @position[:trail_type] || :fixed_pct
      trail_val = @position[:trail_value]

      opt_idx = nil
      if @option_series
        opt_idx = @option_series.candles.find_index { |c| c.timestamp == timestamp }
      end

      case trail_type.to_sym
      when :fixed_pct
        val = trail_val || 15.0
        @mfe * (1.0 - (val / 100.0))
      when :fixed_pts
        val = trail_val || 15.0
        @mfe - val
      when :atr
        if @option_series && opt_idx
          atr_val = @option_series.atr(14)[opt_idx] || 0.0
          mult = trail_val || 2.0
          @mfe - (mult * atr_val)
        else
          @mfe * 0.85
        end
      when :chandelier
        if @option_series && opt_idx
          lookback = 14
          mult = trail_val || 2.0
          atr_val = @option_series.atr(lookback)[opt_idx] || 0.0
          start_idx = [0, opt_idx - lookback + 1].max
          highest_high = @option_series.candles[start_idx..opt_idx].map(&:high).max || @mfe
          highest_high - (mult * atr_val)
        else
          @mfe * 0.85
        end
      when :ema
        if @option_series && opt_idx
          period = trail_val || 20
          @option_series.ema(period)[opt_idx]
        else
          @mfe * 0.85
        end
      when :supertrend
        st_data = @indicator_series.supertrend(10, 3.0)
        curr_trend = st_data[:trend][candle_index]
        option_type = @position[:option_type]

        if (option_type == :call && !curr_trend) || (option_type == :put && curr_trend)
          option_price
        else
          @trailing_sl || @initial_sl
        end
      when :swing
        lookback = trail_val || 3
        option_type = @position[:option_type]

        swing_val = nil
        (0..50).each do |offset|
          check_idx = candle_index - offset
          break if check_idx.negative?

          if option_type == :call && @indicator_series.swing_low?(check_idx, lookback: lookback)
            swing_val = @indicator_series.candles[check_idx].low
            break
          elsif option_type == :put && @indicator_series.swing_high?(check_idx, lookback: lookback)
            swing_val = @indicator_series.candles[check_idx].high
            break
          end
        end

        if swing_val
          spot = index_candle.close
          if (option_type == :call && spot < swing_val) || (option_type == :put && spot > swing_val)
            option_price
          else
            @trailing_sl || @initial_sl
          end
        else
          @trailing_sl || @initial_sl
        end
      when :donchian
        period = trail_val || 20
        option_type = @position[:option_type]
        spot = index_candle.close

        if option_type == :call
          low_bound = @indicator_series.donchian_low(period)[candle_index]
          if spot < low_bound
            option_price
          else
            @trailing_sl || @initial_sl
          end
        elsif option_type == :put
          high_bound = @indicator_series.donchian_high(period)[candle_index]
          if spot > high_bound
            option_price
          else
            @trailing_sl || @initial_sl
          end
        else
          @trailing_sl || @initial_sl
        end
      when :adaptive
        held_mins = ((timestamp - @position[:entry_time]) / 60.0).to_i
        base_trail = trail_val || 15.0
        adjusted_trail = [5.0, base_trail - (held_mins * 0.5)].max
        @mfe * (1.0 - (adjusted_trail / 100.0))
      when :hybrid
        fixed_sl = @mfe * 0.90
        swing_val = nil
        (0..30).each do |offset|
          check_idx = candle_index - offset
          break if check_idx.negative?
          if @position[:option_type] == :call && @indicator_series.swing_low?(check_idx, lookback: 3)
            swing_val = @indicator_series.candles[check_idx].low
            break
          end
        end

        swing_triggered = swing_val && index_candle.close < swing_val
        if swing_triggered
          option_price
        else
          fixed_sl
        end
      else
        val = trail_val || 15.0
        @mfe * (1.0 - (val / 100.0))
      end
    end

    def check_underlying_exit?(candle_index, index_candle)
      return false unless @position[:underlying_trend_exit]

      ema_20 = @indicator_series.ema(20)[candle_index]
      return false unless ema_20

      option_type = @position[:option_type]
      if option_type == :call && index_candle.close < ema_20
        true
      else
        option_type == :put && index_candle.close > ema_20
      end
    end
  end
end
