# frozen_string_literal: true

module Entries
  # Full pipeline for credit spread / option selling entry:
  # 1. Check IV Rank inline (ensures adequate premium to sell)
  # 2. Select short & long hedge strikes (Options::StrikeSelector)
  # 3. Size position based on margin risk (Capital::SellingPositionSizer)
  # 4. Build hedge-first ordered legs (Strategies::CreditSpreadStrategy)
  # 5. Execute with rollback protection (Orders::MultiLegExecutor)
  # 6. Persist LegGroup and update PositionTrackers
  class SellingEntryPipeline
    attr_reader :index_cfg, :direction, :regime, :mode

    def self.run(index_cfg:, direction:, regime:, mode: nil)
      new(index_cfg: index_cfg, direction: direction, regime: regime, mode: mode).call
    end

    def initialize(index_cfg:, direction:, regime:, mode: nil)
      @index_cfg = index_cfg
      @direction = direction
      @regime = regime
      @mode = (mode || (AlgoConfig.fetch.dig(:paper_trading, :enabled) ? :paper : :live)).to_sym
    end

    def call
      iv_rank = fetch_iv_rank
      min_rank = (AlgoConfig.fetch.dig(:risk, :selling_iv_rank_gate, :min_iv_rank) || 0.35).to_f
      if iv_rank && iv_rank < min_rank
        Rails.logger.info("[SellingEntryPipeline] IV Rank too low for #{@index_cfg[:key]}: #{iv_rank.round(2)} < #{min_rank}")
        return { success: false, reason: :low_iv_rank }
      end

      strategy_type = strategy_type_for_regime
      strikes = select_strikes(strategy_type)
      unless strikes
        Rails.logger.warn("[SellingEntryPipeline] Strike selection failed for #{@index_cfg[:key]} (#{strategy_type})")
        return { success: false, reason: :strike_selection_failed }
      end

      spread_width = strikes[:spread_width]
      net_premium = calculate_net_premium(strikes[:short_leg], strikes[:long_leg])
      quantity = Capital::SellingPositionSizer.calculate_lots(
        index_key: @index_cfg[:key],
        spread_width: spread_width,
        net_premium: net_premium,
        mode: mode
      )

      strategy = Strategies::CreditSpreadStrategy.new(
        index_key: @index_cfg[:key],
        strategy_type: strategy_type,
        quantity: quantity
      )
      legs = strategy.build_legs(
        short_leg_candidate: strikes[:short_leg],
        long_leg_candidate: strikes[:long_leg]
      )

      execution_result = Orders::MultiLegExecutor.execute(legs: legs, mode: mode)
      unless execution_result[:success]
        Rails.logger.error("[SellingEntryPipeline] Multi-leg execution failed: #{execution_result[:error]}")
        return { success: false, reason: execution_result[:error], rolled_back: execution_result[:rolled_back] }
      end

      create_leg_group(execution_result, iv_rank)
    rescue StandardError => e
      Rails.logger.error("[SellingEntryPipeline] #{e.class}: #{e.message}")
      { success: false, error: e.message }
    end

    private

    def strategy_type_for_regime
      @direction == :bullish ? :bull_put_spread : :bear_call_spread
    end

    def select_strikes(strategy_type)
      selector = Options::StrikeSelector.new
      selector.select_selling_strikes(
        index_key: @index_cfg[:key],
        strategy_type: strategy_type
      )
    end

    def calculate_net_premium(short_leg, long_leg)
      short_price = short_leg[:ltp] || short_leg[:last_price] || 0
      long_price = long_leg[:ltp] || long_leg[:last_price] || 0
      [short_price.to_f - long_price.to_f, 1.0].max
    end

    def fetch_iv_rank
      index_key = @index_cfg[:key].to_s.downcase
      current_iv = fetch_current_iv
      return nil unless current_iv&.positive?

      historical = IvSnapshot.historical_iv(index_key: index_key, days: 30)
      return nil if historical.size < 5

      iv_min = historical.min
      iv_max = historical.max
      return 0.5 if iv_max == iv_min

      ((current_iv - iv_min) / (iv_max - iv_min)).clamp(0.0, 1.0)
    end

    def fetch_current_iv
      index_key = @index_cfg[:key].to_s.downcase
      snapshot = IvSnapshot.latest_for(index_key: index_key)
      snapshot&.atm_iv&.to_f
    end

    def create_leg_group(result, _iv_rank)
      instrument = Instrument.find_by(symbol_name: @index_cfg[:key].to_s.upcase) ||
                   Instrument.find_by(underlying_symbol: @index_cfg[:key].to_s.upcase)
      first_leg = result[:legs]&.first&.dig(:leg) || {}
      expiry = first_leg[:expiry] || Time.zone.today
      qty = first_leg[:quantity] || @index_cfg[:lot_size] || 1

      group = LegGroup.create_from_executor_result!(
        result,
        instrument: instrument,
        strategy_type: strategy_type_for_regime.to_s,
        expiry: expiry,
        quantity: qty
      )

      { success: true, leg_group: group, legs: result[:legs] }
    end
  end
end
