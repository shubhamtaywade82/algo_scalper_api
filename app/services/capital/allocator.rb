# frozen_string_literal: true

require 'bigdecimal'
require_relative '../concerns/broker_fee_calculator'

module Capital
  class Allocator
    # Capital-aware deployment policy based on account size
    # Bands are inclusive upper-bounds. Smaller accounts get higher allocation % but lower risk %
    CAPITAL_BANDS = [
      { upto: 75_000, alloc_pct: 0.40, risk_per_trade_pct: 0.060, daily_max_loss_pct: 0.060 }, # small a/c (≈ ₹50k)
      { upto: 150_000, alloc_pct: 0.35, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.070 }, # ≈ ₹1L
      { upto: 300_000, alloc_pct: 0.30, risk_per_trade_pct: 0.040, daily_max_loss_pct: 0.070 }, # ≈ ₹2–3L
      { upto: Float::INFINITY, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 }
    ].freeze

    class << self
      def paper_trading_balance
        AlgoConfig.fetch.dig(:paper_trading, :balance) || 100_000.0
      end

      def qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier: 1)
        multiplier = effective_multiplier(scale_multiplier)
        capital_available = available_cash

        return 0 unless valid_for_allocation?(index_cfg, entry_price, derivative_lot_size, capital_available)

        @index_key = index_cfg[:key] || 'UNKNOWN'

        # Check if Kelly-based position sizing is enabled
        if kelly_based_sizing_enabled?(index_cfg)
          return calculate_kelly_based_quantity(
            index_cfg: index_cfg,
            entry_price: entry_price,
            derivative_lot_size: derivative_lot_size,
            capital_available: capital_available,
            multiplier: multiplier
          )
        end

        # Check if rupee-based position sizing is enabled
        if rupee_based_sizing_enabled?
          return calculate_rupee_based_quantity(
            index_cfg: index_cfg,
            entry_price: entry_price,
            derivative_lot_size: derivative_lot_size,
            capital_available: capital_available,
            multiplier: multiplier
          )
        end

        calculate_and_apply_quantity(
          index_cfg: index_cfg,
          entry_price: entry_price,
          derivative_lot_size: derivative_lot_size,
          capital_available: capital_available,
          multiplier: multiplier
        )
      rescue StandardError => e
        log_allocation_error(index_cfg, e)
        0
      end

      def deployment_policy(balance)
        band = find_capital_band(balance)
        build_policy_with_overrides(band)
      end

      def available_cash
        wallet = Orders.config.gateway.wallet_snapshot
        cash = convert_to_bigdecimal(wallet.fetch(:cash, 0))
        return cash if cash.positive?
        return BigDecimal(paper_trading_balance.to_s) if Rails.env.test?

        cash
      rescue StandardError => e
        log_balance_fetch_error(e)
        BigDecimal(paper_trading_balance.to_s)
      end

      private

      # Max fraction of available cash for position buy value (percentage path and rupee-based cap).
      # Order: per-index capital_alloc_pct → sizing.allocation_cap_pct → deployment band alloc_pct.
      def effective_allocation_pct(index_cfg, capital_available)
        cfg = index_cfg || {}
        return cfg[:capital_alloc_pct].to_f if cfg[:capital_alloc_pct].present?

        global_cap = sizing_allocation_cap_pct
        return global_cap.to_f if global_cap.present?

        deployment_policy(capital_available.to_f)[:alloc_pct]
      end

      def sizing_allocation_cap_pct
        AlgoConfig.fetch.dig(:sizing, :allocation_cap_pct)
      rescue StandardError
        nil
      end

      def normalize_multiplier(scale_multiplier)
        [scale_multiplier.to_i, 1].max
      end

      def effective_multiplier(scale_multiplier)
        base_multiplier = normalize_multiplier(scale_multiplier)
        midday_multiplier = post_1100_multiplier
        adjusted = base_multiplier
        adjusted = (adjusted * midday_multiplier).floor if midday_multiplier < 1.0 && post_1100?

        regime_cut = time_regime_size_multiplier
        adjusted = (adjusted * regime_cut).floor if regime_cut < 1.0

        peak_cut = post_peak_size_cut
        adjusted = (adjusted * peak_cut).floor if peak_cut < 1.0

        [adjusted, 1].max
      end

      # Scales position size down when the current market session is theta/IV-decay
      # dominant. An option buyer's edge is weakest in the Chop/Theta zone (S3) and the
      # Close/Gamma zone (S4) — risking full size there compounds the wasting-asset
      # problem. Uses Live::TimeRegimeService's existing session classification (the
      # same regimes that already gate entries) so sizing and entry logic agree on
      # which windows are dangerous.
      def time_regime_size_multiplier
        return 1.0 unless decay_aware_sizing_enabled?

        regime_service = Live::TimeRegimeService.instance
        regime = regime_service.current_regime

        case regime
        when Live::TimeRegimeService::CHOP_DECAY
          decay_sizing_cfg.fetch(:chop_decay_factor, 0.5).to_f
        when Live::TimeRegimeService::CLOSE_GAMMA
          decay_sizing_cfg.fetch(:close_gamma_factor, 0.6).to_f
        else
          1.0
        end
      rescue StandardError => e
        Rails.logger.warn("[Allocator] time_regime_size_multiplier error: #{e.message}")
        1.0
      end

      def decay_aware_sizing_enabled?
        decay_sizing_cfg.fetch(:enabled, true) != false
      end

      def decay_sizing_cfg
        AlgoConfig.fetch.dig(:capital_allocator, :decay_aware_sizing) || {}
      rescue StandardError
        {}
      end

      # Cuts size when intraday net PnL gives back a meaningful fraction of the
      # day's peak. Reduces overtrading after the equity curve has rolled over.
      def post_peak_size_cut
        cfg = AlgoConfig.fetch.dig(:capital_allocator, :post_peak_size_cut) || {}
        return 1.0 if cfg[:enabled] == false

        min_peak    = cfg[:min_peak].to_f
        min_peak    = 2_000.0 unless min_peak.positive?
        warn_ratio  = cfg[:giveback_ratio].to_f
        warn_ratio  = 0.50 unless warn_ratio.positive?
        size_factor = cfg[:size_factor].to_f
        size_factor = 0.5 unless size_factor.positive? && size_factor <= 1.0

        peak = Portfolio::PnlTracker.peak_pnl
        return 1.0 if peak < min_peak

        net = Portfolio::PnlTracker.net_pnl
        return 1.0 if net >= peak * warn_ratio

        Rails.logger.info(
          "[Allocator] post_peak_size_cut active: peak=₹#{peak.round(2)} " \
          "net=₹#{net.round(2)} → size×#{size_factor}"
        )
        size_factor
      rescue StandardError => e
        Rails.logger.warn("[Allocator] post_peak_size_cut error: #{e.message}")
        1.0
      end

      def post_1100_multiplier
        value = AlgoConfig.fetch.dig(:sizing, :post_1100_multiplier)
        return 1.0 if value.nil?

        multiplier = value.to_f
        multiplier.positive? ? multiplier : 1.0
      rescue StandardError
        1.0
      end

      def post_1100?
        current_ist_time = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        current_ist_time >= '11:00'
      end

      def valid_for_allocation?(index_cfg, entry_price, derivative_lot_size, capital_available)
        return log_and_return_false("[Capital] Invalid capital snapshot for #{index_cfg[:key]}") unless finite_money?(capital_available)

        entry_f = entry_price.to_f
        unless entry_f.finite? && entry_f.positive?
          return log_and_return_false("[Capital] Invalid entry price for #{index_cfg[:key]}: #{entry_price}")
        end

        return log_and_return_false("[Capital] Available capital is zero for #{index_cfg[:key]}") if capital_available.zero?

        lot_size = derivative_lot_size.to_i
        return log_and_return_false("[Capital] Invalid lot size for #{index_cfg[:key]}: #{lot_size}") if lot_size <= 0

        unless can_afford_minimum_lot?(
          entry_price, lot_size, capital_available
        )
          return log_insufficient_capital(index_cfg, entry_price, lot_size,
                                          capital_available)
        end

        true
      end

      def can_afford_minimum_lot?(entry_price, lot_size, capital_available)
        min_lot_cost = entry_price.to_f * lot_size
        capital_available >= min_lot_cost
      end

      def log_insufficient_capital(index_cfg, entry_price, lot_size, capital_available)
        min_lot_cost = entry_price.to_f * lot_size
        Rails.logger.warn("[Capital] Insufficient capital for minimum lot for #{index_cfg[:key]}: Available ₹#{capital_available}, Required ₹#{min_lot_cost} (price: ₹#{entry_price}, lot_size: #{lot_size})")
        false
      end

      def log_and_return_false(message)
        Rails.logger.warn(message)
        false
      end

      def calculate_and_apply_quantity(index_cfg:, entry_price:, derivative_lot_size:, capital_available:, multiplier:)
        @index_key = index_cfg[:key] || 'UNKNOWN'
        capital_available_f = capital_available.to_f
        entry_price_f = entry_price.to_f
        lot_size = derivative_lot_size.to_i

        policy = deployment_policy(capital_available_f)
        effective_alloc_pct = effective_allocation_pct(index_cfg, capital_available_f)
        effective_risk_pct = policy[:risk_per_trade_pct]

        quantity = calculate_quantity_by_constraints(
          capital_available_f: capital_available_f,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          effective_alloc_pct: effective_alloc_pct,
          effective_risk_pct: effective_risk_pct,
          multiplier: multiplier
        )

        final_quantity = apply_quantity_safety_checks(
          quantity: quantity,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          capital_available_f: capital_available_f
        )

        log_allocation_breakdown(
          capital_available: capital_available,
          policy: policy,
          effective_alloc_pct: effective_alloc_pct,
          effective_risk_pct: effective_risk_pct,
          multiplier: multiplier,
          entry_price_f: entry_price_f,
          lot_size: lot_size,
          final_quantity: final_quantity
        )

        final_quantity
      end

      def calculate_quantity_by_constraints(capital_available_f:, entry_price_f:, lot_size:, effective_alloc_pct:,
                                            effective_risk_pct:, multiplier:)
        max_by_allocation = calculate_max_by_allocation(capital_available_f, entry_price_f, lot_size,
                                                        effective_alloc_pct, multiplier)
        max_by_risk = calculate_max_by_risk(capital_available_f, entry_price_f, lot_size, effective_risk_pct,
                                            multiplier)

        [max_by_allocation, max_by_risk].min
      end

      def calculate_max_by_allocation(capital_available_f, entry_price_f, lot_size, effective_alloc_pct, multiplier)
        allocation = capital_available_f * effective_alloc_pct
        scaled_allocation = [allocation * multiplier, capital_available_f].min
        cost_per_lot = entry_price_f * lot_size

        (scaled_allocation / cost_per_lot).floor * lot_size
      end

      def calculate_max_by_risk(capital_available_f, entry_price_f, lot_size, effective_risk_pct, multiplier)
        risk_capital = capital_available_f * effective_risk_pct
        risk_capital_scaled = [risk_capital * multiplier, capital_available_f].min
        stop_loss_per_share = entry_price_f * configured_sl_pct

        (risk_capital_scaled / stop_loss_per_share).floor * lot_size
      end

      # Single source of truth for stop-loss percentage, shared with
      # Live::UnifiedExitChecker#build_exit_config so risk-based sizing is
      # calibrated to the same stop distance the exit engine will actually use.
      def configured_sl_pct
        algo_cfg = AlgoConfig.fetch
        risk_cfg = algo_cfg[:risk] || {}
        exit_cfg = algo_cfg[:exit] || {}
        (risk_cfg[:sl_pct] || exit_cfg.dig(:stop_loss, :value) || 0.12).to_f
      end

      def configured_tp_pct
        algo_cfg = AlgoConfig.fetch
        risk_cfg = algo_cfg[:risk] || {}
        exit_cfg = algo_cfg[:exit] || {}
        (exit_cfg[:take_profit] || risk_cfg[:tp_pct] || 0.50).to_f
      end

      def apply_quantity_safety_checks(quantity:, entry_price_f:, lot_size:, capital_available_f:)
        final_quantity = enforce_lot_size_constraints(quantity, lot_size)
        adjust_if_exceeds_capital(final_quantity, entry_price_f, lot_size, capital_available_f)
      end

      def enforce_lot_size_constraints(quantity, lot_size)
        [[quantity, lot_size].max, lot_size * 100].min
      end

      def adjust_if_exceeds_capital(final_quantity, entry_price_f, lot_size, capital_available_f)
        final_buy_value = entry_price_f * final_quantity
        return final_quantity if final_buy_value <= capital_available_f

        reduce_to_affordable_quantity(entry_price_f, lot_size, capital_available_f)
      end

      def reduce_to_affordable_quantity(entry_price_f, lot_size, capital_available_f)
        cost_per_lot = entry_price_f * lot_size
        max_affordable_lots = (capital_available_f / cost_per_lot).floor
        final_quantity = max_affordable_lots * lot_size

        [final_quantity, lot_size].max
      end

      def find_capital_band(balance)
        CAPITAL_BANDS.find { |b| balance <= b[:upto] } || CAPITAL_BANDS.last
      end

      def build_policy_with_overrides(band)
        {
          upto: band[:upto],
          alloc_pct: band[:alloc_pct],
          risk_per_trade_pct: band[:risk_per_trade_pct],
          daily_max_loss_pct: band[:daily_max_loss_pct]
        }
      end

      def allocation_percentage_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:alloc_pct] || ENV['ALLOC_PCT']&.to_f
      end

      def risk_per_trade_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:risk_per_trade_pct] || ENV['RISK_PER_TRADE_PCT']&.to_f
      end

      def daily_max_loss_with_override(band)
        # Prefer algo.yml config, ENV as fallback for testing
        band[:daily_max_loss_pct] || ENV['DAILY_MAX_LOSS_PCT']&.to_f
      end

      def convert_to_bigdecimal(value)
        result = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
        Rails.logger.debug { "[Capital] Available cash: ₹#{result}" }
        result
      end

      def log_balance_fetch_error(error)
        Rails.logger.error("[Capital] Failed to fetch available cash: #{error.class} - #{error.message}")
        Rails.logger.error("[Capital] Backtrace: #{error.backtrace.first(3).join(', ')}")
      end

      def log_allocation_error(index_cfg, error)
        Rails.logger.error("[Capital] Allocator failed for #{index_cfg[:key]}: #{error.class} - #{error.message}")
        Rails.logger.error("[Capital] Backtrace: #{error.backtrace.first(3).join(', ')}")
      end

      def log_allocation_breakdown(capital_available:, entry_price_f:, lot_size:, final_quantity:, policy: nil,
                                   effective_alloc_pct: nil, effective_risk_pct: nil, multiplier: nil)
        capital_available_f = capital_available.to_f
        cost_per_lot = entry_price_f * lot_size
        index_key = @index_key || 'UNKNOWN'

        reason = if final_quantity.zero?
                   'insufficient_capital'
                 elsif final_quantity < lot_size
                   'below_minimum_lot'
                 else
                   'allocated'
                 end

        Rails.logger.info(
          "[Allocator] index:#{index_key} lot_cost:₹#{format_money(cost_per_lot)} " \
          "capital:₹#{format_money(capital_available_f)} qty:#{final_quantity} reason:#{reason}"
        )
      end

      # Kelly-based position sizing: derive quantity from Kelly Criterion formula
      # Formula: f* = p - (1-p)/r
      def calculate_kelly_based_quantity(index_cfg:, entry_price:, derivative_lot_size:, capital_available:, multiplier:)
        sizing_cfg = AlgoConfig.fetch[:kelly_sizing] || {}
        return 0 unless sizing_cfg[:enabled]

        entry_bd = BigDecimal(entry_price.to_s)
        return 0 unless entry_bd.finite? && entry_bd.positive?

        # Attempt to load dynamic historical stats
        strategy_name = index_cfg[:entry_strategy] || index_cfg[:strategy]
        index_key = index_cfg[:key] || @index_key
        stats = OptionsBuying::PerformanceDb.stats_for(strategy_name, index_key)

        if stats
          p = stats[:win_rate].to_f
          r = stats[:payout_ratio].to_f
          Rails.logger.info("[Allocator] KELLY_BASED using database stats: p=#{p.round(4)}, r=#{r.round(4)} (n=#{stats[:sample_size]})")
        else
          # Fallback: p = confidence (0.0 to 1.0)
          p = (index_cfg[:confidence] || sizing_cfg[:default_win_rate] || 0.55).to_f
          # r = Reward-to-Risk ratio. Option premiums swing far more than equity-style
          # 2%/4% defaults, so fall back to the actual configured SL/TP percentages
          # (same source as calculate_max_by_risk and Live::UnifiedExitChecker).
          default_stop_price = entry_bd * (1 - configured_sl_pct)
          default_target_price = entry_bd * (1 + configured_tp_pct)
          risk = (entry_bd - BigDecimal((index_cfg[:stop_loss] || default_stop_price).to_s)).abs
          reward = (BigDecimal((index_cfg[:target] || default_target_price).to_s) - entry_bd).abs
          r = risk.positive? ? (reward / risk).to_f : (sizing_cfg[:default_payout_ratio] || 1.5).to_f
          Rails.logger.info("[Allocator] KELLY_BASED using fallback defaults: p=#{p.round(4)}, r=#{r.round(4)}")
        end

        # Calculate Kelly fraction f*
        kelly_f = p - ((1.0 - p) / r)
        # Apply safety factor (Half-Kelly or Fractional Kelly)
        safety_factor = (sizing_cfg[:safety_factor] || 0.5).to_f
        max_alloc = (sizing_cfg[:max_capital_allocation_pct] || 0.20).to_f
        f_star = [kelly_f * safety_factor, max_alloc].min

        return 0 if f_star <= 0

        # buy_value = capital_available * f_star
        buy_value = capital_available * BigDecimal(f_star.to_s)
        lot_cost = entry_bd * derivative_lot_size
        max_lots = (buy_value / lot_cost).floor

        # Apply multiplier
        max_lots = (max_lots * multiplier).to_i
        quantity = max_lots * derivative_lot_size

        # Minimum 1 lot
        quantity = [quantity, derivative_lot_size.to_i].max

        # Affordability check
        max_affordable_lots = (capital_available / lot_cost).floor
        final_quantity = [quantity, max_affordable_lots * derivative_lot_size.to_i].min

        Rails.logger.info(
          "[Allocator] KELLY_BASED index:#{@index_key} p:#{p.round(2)} r:#{r.round(2)} " \
          "f_star:#{f_star.round(3)} buy_value:₹#{format_money(buy_value)} " \
          "qty:#{final_quantity}"
        )

        final_quantity
      end

      def kelly_based_sizing_enabled?(index_cfg)
        cfg = AlgoConfig.fetch[:kelly_sizing]
        return false unless cfg && cfg[:enabled] == true

        index_cfg[:confidence].present? ||
          OptionsBuying::PerformanceDb.stats_for(index_cfg[:entry_strategy] || index_cfg[:strategy], index_cfg[:key]).present?
      end

      # Rupee-based position sizing: derive quantity from fixed ₹ risk
      # Formula: quantity = floor(risk_rupees / (stop_distance_rupees × lot_size)) × lot_size
      def calculate_rupee_based_quantity(entry_price:, derivative_lot_size:, capital_available:, multiplier:, index_cfg: {})
        sizing_cfg = position_sizing_config
        return 0 unless sizing_cfg && sizing_cfg[:enabled]

        entry_bd = BigDecimal(entry_price.to_s)
        return 0 unless entry_bd.finite? && entry_bd.positive?
        return 0 unless finite_money?(capital_available)

        risk_rupees = BigDecimal((sizing_cfg[:risk_rupees] || 1000).to_s)
        index_key = (@index_key || index_cfg[:key] || 'UNKNOWN').to_s

        # Deduct broker fees from risk capital (₹40 per trade: entry + exit)
        # This ensures net risk after fees matches the target risk
        broker_fees = BrokerFeeCalculator.fee_per_trade
        net_risk_rupees = risk_rupees - broker_fees

        # Get index-specific stop distance or fallback to global
        index_stop_distances = sizing_cfg[:index_stop_distances] || {}
        stop_distance_rupees = if index_stop_distances[index_key.to_sym] || index_stop_distances[index_key.to_s]
                                 BigDecimal((index_stop_distances[index_key.to_sym] || index_stop_distances[index_key.to_s]).to_s)
                               else
                                 BigDecimal((sizing_cfg[:stop_distance_rupees] || 8).to_s)
                               end
        lot_size = derivative_lot_size.to_i

        return 0 if stop_distance_rupees.zero? || lot_size.zero?
        return 0 if net_risk_rupees <= 0 # Not enough risk capital after fees

        # Calculate risk per lot
        risk_per_lot = stop_distance_rupees * lot_size

        # Calculate max lots based on net risk (after fees)
        max_lots_by_risk = (net_risk_rupees / risk_per_lot).floor

        # Apply multiplier
        max_lots = max_lots_by_risk * multiplier

        # Calculate quantity (must be lot-aligned)
        quantity = max_lots * lot_size

        # Ensure minimum 1 lot
        quantity = [quantity, lot_size].max

        # Check capital allocation constraint (alloc_pct caps total buy value)
        cost_per_lot = BigDecimal(entry_price.to_s) * lot_size
        alloc_pct = effective_allocation_pct(index_cfg, capital_available.to_f)
        max_allocation = capital_available * BigDecimal(alloc_pct.to_s)
        max_lots_by_alloc = (max_allocation / cost_per_lot).floor
        max_alloc_quantity = max_lots_by_alloc * lot_size

        # Also check raw affordability
        max_affordable_lots = (capital_available / cost_per_lot).floor
        max_affordable_quantity = max_affordable_lots * lot_size

        # Take minimum of risk-based, allocation-based, and capital-based quantity
        final_quantity = [quantity, max_alloc_quantity, max_affordable_quantity].min

        # Ensure at least 1 lot
        final_quantity = [final_quantity, lot_size].max

        # Log breakdown
        alloc_pct_f = alloc_pct.to_f
        pct_label = alloc_pct_f.finite? ? alloc_pct_f.round(0).to_i : 'n/a'
        buy_value = entry_price.to_f * final_quantity
        Rails.logger.info(
          "[Allocator] RUPEES_BASED index:#{index_key} risk:₹#{risk_rupees} " \
          "fees:₹#{broker_fees} net_risk:₹#{net_risk_rupees} " \
          "stop_dist:₹#{stop_distance_rupees} risk_per_lot:₹#{risk_per_lot} " \
          "max_lots:#{max_lots_by_risk} alloc_cap:#{max_lots_by_alloc}(#{pct_label}%) " \
          "qty:#{final_quantity} buy_value:₹#{format_money(buy_value)}"
        )

        final_quantity
      end

      def rupee_based_sizing_enabled?
        sizing_cfg = position_sizing_config
        sizing_cfg && sizing_cfg[:enabled] == true
      end

      def position_sizing_config
        AlgoConfig.fetch[:position_sizing]
      rescue StandardError
        nil
      end

      def finite_money?(value)
        case value
        when BigDecimal then value.finite?
        else value.to_f.finite?
        end
      end

      def format_money(value)
        f = value.to_f
        f.finite? ? format('%.2f', f) : 'n/a'
      end
    end
  end
end
