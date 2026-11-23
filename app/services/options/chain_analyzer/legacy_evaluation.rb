# frozen_string_literal: true

module Options
  class ChainAnalyzer
    module LegacyEvaluation
      def self.included(base)
        base.include(LegacyFilters)
        base.const_set(:BEHAVIOR_STRATEGIES, BEHAVIOR_STRATEGIES) unless base.const_defined?(:BEHAVIOR_STRATEGIES)
      end

      BEHAVIOR_STRATEGIES = {
        strike_selection: {
          method: :configure_strike_selection,
          default: { offset: 2, include_atm: true, max_otm: 2 },
          index_specific: {
            nifty: { offset: 2, include_atm: true, max_otm: 2 },
            sensex: { offset: 3, include_atm: true, max_otm: 3 },
            banknifty: { offset: 2, include_atm: false, max_otm: 2 }
          }
        },
        liquidity_filter: {
          method: :configure_liquidity_filter,
          default: { min_oi: 50_000, min_volume: 10_000, max_spread_pct: 3.0 },
          index_specific: {
            nifty: { min_oi: 100_000, min_volume: 50_000, max_spread_pct: 3.0 },
            sensex: { min_oi: 50_000, min_volume: 25_000, max_spread_pct: 3.5 },
            banknifty: { min_oi: 75_000, min_volume: 30_000, max_spread_pct: 3.0 }
          }
        },
        volatility_assessment: {
          method: :configure_volatility_assessment,
          default: { low_iv: 10.0, high_iv: 30.0, min_iv: 10.0, max_iv: 60.0 },
          index_specific: {
            nifty: { low_iv: 10.0, high_iv: 30.0, min_iv: 10.0, max_iv: 60.0 },
            sensex: { low_iv: 12.0, high_iv: 40.0, min_iv: 12.0, max_iv: 60.0 },
            banknifty: { low_iv: 15.0, high_iv: 45.0, min_iv: 15.0, max_iv: 60.0 }
          }
        },
        position_sizing: {
          method: :configure_position_sizing,
          default: { risk_per_trade: 0.01, max_capital_utilization: 0.10 },
          index_specific: {
            nifty: { risk_per_trade: 0.01, max_capital_utilization: 0.10 },
            sensex: { risk_per_trade: 0.01, max_capital_utilization: 0.10 },
            banknifty: { risk_per_trade: 0.02, max_capital_utilization: 0.10 }
          }
        },
        delta_filter: {
          method: :configure_delta_filter,
          default: { min_delta: 0.08, time_based: true },
          index_specific: {
            nifty: { min_delta: 0.08, time_based: true },
            sensex: { min_delta: 0.08, time_based: true },
            banknifty: { min_delta: 0.10, time_based: true }
          }
        }
      }.freeze

      attr_reader :index_cfg, :config, :chain_data, :sorted_strikes, :spot_price, :expiry_date, :instrument, :index_symbol

      def initialize(index:, data_provider: nil, config: {})
        @index_cfg = normalize_index(index)
        @provider = data_provider
        @custom_config = config || {}
        @index_symbol = normalize_index_symbol(@index_cfg[:key])
        @config = load_configuration
        @chain_data = nil
        @sorted_strikes = nil
        @spot_price = nil
        @expiry_date = nil
        @instrument = nil
      end

      def load_chain_data!
        @instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
        return false unless @instrument

        expiry_list = @instrument.expiry_list
        return false unless expiry_list&.any?

        @expiry_date = self.class.find_next_expiry(expiry_list)
        return false unless @expiry_date

        chain_data_raw = begin
          @instrument.fetch_option_chain(@expiry_date)
        rescue StandardError => e
          Rails.logger.warn("[Options::ChainAnalyzer] Failed to fetch chain: #{e.class} - #{e.message}")
          nil
        end
        return false unless chain_data_raw

        @chain_data = chain_data_raw
        @spot_price = chain_data_raw[:last_price]&.to_f
        @sorted_strikes = chain_data_raw[:oc]&.keys&.map(&:to_f)&.sort || []
        true
      end

      def recommend_strikes_for_signal(signal, options = {})
        return { strikes: [], option_type: nil, error: 'Chain data not loaded' } unless chain_data_loaded?

        direction = signal.to_sym
        option_type = direction == :bullish ? 'ce' : 'pe'
        strike_config = @config[:strike_selection].merge(options.slice(:offset, :include_atm, :max_otm))
        strike_interval = calculate_strike_interval
        atm_strike = find_atm_strike(@spot_price, strike_interval)
        candidates = generate_candidate_strikes(atm_strike, strike_interval, option_type, strike_config)
        filtered = filter_strikes(candidates, option_type)
        scored = score_strikes(filtered, atm_strike, option_type)

        {
          strikes: scored.pluck(:strike), option_type: option_type, atm_strike: atm_strike,
          spot_price: @spot_price, expiry_date: @expiry_date
        }
      end

      def chain_summary
        return nil unless chain_data_loaded?

        {
          index: @index_cfg[:key], spot_price: @spot_price, expiry_date: @expiry_date,
          total_strikes: @sorted_strikes.size,
          strike_range: @sorted_strikes.any? ? { min: @sorted_strikes.first, max: @sorted_strikes.last } : nil,
          strike_interval: calculate_strike_interval,
          atm_strike: find_atm_strike(@spot_price, calculate_strike_interval),
          timestamp: Time.current
        }
      end

      def assess_volatility(strike, option_type)
        return nil unless chain_data_loaded?

        option_data = get_option_data(strike, option_type)
        return nil unless option_data

        iv = option_data['implied_volatility']&.to_f
        return nil unless iv

        thresholds = @config[:volatility_assessment]
        if iv < thresholds[:low_iv] then :cheap
        elsif iv > thresholds[:high_iv] then :expensive
        else :fair
        end
      end

      def liquidity_status(strike, option_type)
        return nil unless chain_data_loaded?

        option_data = get_option_data(strike, option_type)
        return nil unless option_data

        oi = option_data['oi'].to_i
        volume = option_data['volume'].to_i
        bid = option_data['top_bid_price']&.to_f
        ask = option_data['top_ask_price']&.to_f
        spread_pct = bid && ask && bid.positive? ? ((ask - bid) / bid) : nil
        thresholds = @config[:liquidity_filter]

        {
          oi: oi, volume: volume, spread_pct: spread_pct,
          meets_oi_threshold: oi >= thresholds[:min_oi],
          meets_volume_threshold: volume >= thresholds[:min_volume],
          meets_spread_threshold: spread_pct.nil? || spread_pct <= (thresholds[:max_spread_pct] / 100.0),
          overall_liquidity: self.class.calculate_liquidity_score(oi, volume, spread_pct)
        }
      end

      def analyze_strike(strike, option_type)
        return nil unless chain_data_loaded?

        option_data = get_option_data(strike, option_type)
        return nil unless option_data

        greeks = option_data['greeks'] || {}
        strike_interval = calculate_strike_interval
        atm_strike = find_atm_strike(@spot_price, strike_interval)

        {
          strike: strike, option_type: option_type, last_price: option_data['last_price']&.to_f,
          iv: option_data['implied_volatility']&.to_f, oi: option_data['oi']&.to_i,
          volume: option_data['volume']&.to_i, bid: option_data['top_bid_price']&.to_f,
          ask: option_data['top_ask_price']&.to_f, delta: greeks['delta']&.to_f,
          gamma: greeks['gamma']&.to_f, theta: greeks['theta']&.to_f, vega: greeks['vega']&.to_f,
          distance_from_atm: (strike - atm_strike).abs,
          strike_type: classify_strike(strike, atm_strike, strike_interval, option_type),
          volatility_assessment: assess_volatility(strike, option_type),
          liquidity_status: liquidity_status(strike, option_type)
        }
      end

      def calculate_position_size(capital, option_price, risk_params = {})
        return 0 unless capital&.positive? && option_price&.positive?

        params = @config[:position_sizing].merge(risk_params)
        risk_amount = capital * params[:risk_per_trade]
        max_capital_used = capital * params[:max_capital_utilization]

        lots_by_risk = (risk_amount / option_price).floor
        lots_by_capital = (max_capital_used / option_price).floor
        [lots_by_risk, lots_by_capital].min
      end

      def select_candidates(limit: 2, direction: DEFAULT_DIRECTION)
        picks = self.class.pick_strikes(
          index_cfg: @index_cfg,
          direction: direction.presence&.to_sym || DEFAULT_DIRECTION
        )
        return [] if picks.blank?

        picks.first([limit.to_i, 1].max).map { |pick| decorate_pick(pick) }
      rescue StandardError => e
        Rails.logger.error("[Options::ChainAnalyzer] select_candidates failed: #{e.class} - #{e.message}")
        []
      end

      private

      def normalize_index(index)
        return index.deep_symbolize_keys if index.respond_to?(:deep_symbolize_keys)

        Array(index).transform_keys(&:to_sym)
      end

      def normalize_index_symbol(symbol)
        symbol.to_s.downcase.to_sym
      end

      def load_configuration
        algo_config = AlgoConfig.fetch[:option_chain] || {}
        cfg = {}
        BEHAVIOR_STRATEGIES.each_value do |sc|
          key = sc[:method]
          specific = sc[:index_specific][@index_symbol]
          cfg[key] = (@custom_config[key] || specific || sc[:default] || algo_config).dup
        end

        cfg[:strike_selection] = cfg[:configure_strike_selection]
        cfg[:liquidity_filter] = cfg[:configure_liquidity_filter]
        cfg[:volatility_assessment] = cfg[:configure_volatility_assessment]
        cfg[:position_sizing] = cfg[:configure_position_sizing]
        cfg[:delta_filter] = cfg[:configure_delta_filter]
        cfg[:lot_size] = Trading::LotCalculator.lot_size_for(@index_cfg[:key])
        cfg[:point_value] = @index_cfg[:point_value]&.to_f || 25.0
        cfg
      end

      def chain_data_loaded?
        @chain_data.present? && @sorted_strikes&.any?
      end
    end
  end
end
