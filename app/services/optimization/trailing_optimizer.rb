# frozen_string_literal: true

module Optimization
  class TrailingOptimizer
    PARAM_GRID = {
      early_trigger: [0.03, 0.04, 0.05, 0.06],
      breakeven_trigger: [0.08, 0.10, 0.12, 0.15],
      activation_trigger: [0.15, 0.18, 0.20, 0.25],
      trailing_distance: [0.20, 0.22, 0.25, 0.30, 0.35]
    }.freeze

    def initialize(index_key: 'NIFTY')
      @index_key = index_key.to_s.upcase
      @analytics = TradeAnalytic.joins(:position_tracker)
                                .where(position_trackers: { status: 'exited' })
                                .where("position_trackers.meta->>'index_key' = ?", @index_key)
    end

    def optimize
      return nil if @analytics.empty?

      best_score = -Float::INFINITY
      best_params = nil

      combinations = PARAM_GRID[:early_trigger].product(
        PARAM_GRID[:breakeven_trigger],
        PARAM_GRID[:activation_trigger],
        PARAM_GRID[:trailing_distance]
      )

      combinations.each do |early, be, act, dist|
        next if be <= early
        next if act <= be

        params = {
          early_trigger: early,
          breakeven_trigger: be,
          activation_trigger: act,
          trailing_distance: dist
        }

        score = simulate(params)

        if score > best_score
          best_score = score
          best_params = params
        end
      end

      {
        index_key: @index_key,
        best_params: best_params,
        score: best_score,
        trade_count: @analytics.count
      }
    end

    private

    def simulate(params)
      total_profit_pct = 0.0

      @analytics.each do |analytic|
        mfe_pct = analytic.mfe_pct
        mae_pct = analytic.mae_pct

        # Determine exit based on params
        exit_pct = simulate_trade_simple(mfe_pct, mae_pct, params)
        total_profit_pct += exit_pct
      end

      total_profit_pct
    end

    # Simplified trade simulation based on MFE/MAE
    # Returns profit percentage
    def simulate_trade_simple(mfe_pct, mae_pct, params)
      # Phase 3: HWM Trailing
      if mfe_pct >= params[:activation_trigger]
        # Exit at HWM - trailing_distance
        # But cannot be worse than Phase 2 (breakeven)
        exit_pct = mfe_pct - params[:trailing_distance]
        return [exit_pct, 0.0].max
      end

      # Phase 2: Breakeven
      if mfe_pct >= params[:breakeven_trigger]
        return 0.0
      end

      # Phase 1: Early slack
      # early_sl_offset is usually negative (e.g. -0.12)
      early_sl_offset = -0.12

      if mae_pct <= early_sl_offset
        return early_sl_offset
      end

      # Default to 0 profit if none triggered
      0.0
    end
  end
end
