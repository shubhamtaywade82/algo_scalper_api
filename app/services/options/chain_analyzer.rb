# frozen_string_literal: true

require 'bigdecimal'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'

module Options
  # Single configurable analyzer that adapts behavior based on index-specific configuration
  # Follows the same pattern as IndexTechnicalAnalyzer for consistency
  class ChainAnalyzer
    # === CONFIGURABLE BEHAVIOR STRATEGIES (Strategy pattern via config) ===
    BEHAVIOR_STRATEGIES = {
      # Strategy name => {method: :symbol, default: value, index_specific: {}}
      strike_selection: {
        method: :select_strikes_for_signal,
        default: { offset: 2, include_atm: true, max_otm: 2 },
        index_specific: {
          nifty: { offset: 2, include_atm: true, max_otm: 2 },
          sensex: { offset: 3, include_atm: true, max_otm: 1 }, # Sensex uses wider range but fewer strikes
          banknifty: { offset: 2, include_atm: false, max_otm: 2 } # Skip ATM for Bank Nifty
        }
      },

      liquidity_filter: {
        method: :filter_by_liquidity,
        default: { min_oi: 50_000, min_volume: 10_000, max_spread_pct: 0.25 },
        index_specific: {
          nifty: { min_oi: 100_000, min_volume: 50_000, max_spread_pct: 0.20 },
          sensex: { min_oi: 50_000, min_volume: 25_000, max_spread_pct: 0.25 },
          banknifty: { min_oi: 75_000, min_volume: 30_000, max_spread_pct: 0.22 }
        }
      },

      volatility_assessment: {
        method: :assess_volatility,
        default: { low_iv: 15.0, high_iv: 35.0, min_iv: 10.0, max_iv: 60.0 },
        index_specific: {
          nifty: { low_iv: 10.0, high_iv: 30.0, min_iv: 10.0, max_iv: 60.0 },
          sensex: { low_iv: 12.0, high_iv: 40.0, min_iv: 10.0, max_iv: 60.0 },
          banknifty: { low_iv: 15.0, high_iv: 45.0, min_iv: 10.0, max_iv: 60.0 } # Bank Nifty is more volatile
        }
      },

      position_sizing: {
        method: :calculate_position_size,
        default: { risk_per_trade: 1.0, max_capital_utilization: 0.10 },
        index_specific: {
          nifty: { risk_per_trade: 1.0, max_capital_utilization: 0.10 },
          sensex: { risk_per_trade: 0.5, max_capital_utilization: 0.05 }, # More conservative
          banknifty: { risk_per_trade: 0.75, max_capital_utilization: 0.08 }
        }
      },

      delta_filter: {
        method: :filter_by_delta,
        default: { min_delta: 0.08, time_based: true },
        index_specific: {
          nifty: { min_delta: 0.08, time_based: true },
          sensex: { min_delta: 0.10, time_based: true },
          banknifty: { min_delta: 0.08, time_based: true }
        }
      }
    }.freeze

    # Index-specific base configuration (lot sizes, point values, etc.)
    INDEX_BASE_CONFIG = {
      nifty: {
        lot_size: 50,
        point_value: 25,
        strike_interval: 50,
        exchange_segment: 'NFO'
      },
      sensex: {
        lot_size: 10,
        point_value: 1,
        strike_interval: 100,
        exchange_segment: 'BFO'
      },
      banknifty: {
        lot_size: 25,
        point_value: 100,
        strike_interval: 100,
        exchange_segment: 'NFO'
      }
    }.freeze

    DEFAULT_DIRECTION = :bullish

    attr_reader :index_cfg, :index_symbol, :config, :chain_data, :spot_price,
                :sorted_strikes, :strike_interval, :instrument, :expiry_date

    def initialize(index:, data_provider:, config: {}, chain_data: nil, spot_price: nil)
      @index_cfg = normalize_index(index)
      @index_symbol = (@index_cfg[:key] || @index_cfg['key']).to_s.downcase.to_sym
      @provider = data_provider
      @custom_config = config || {}
      @chain_data = chain_data
      @spot_price = spot_price
      @instrument = nil
      @expiry_date = nil
      @sorted_strikes = nil
      @strike_interval = nil
      @config = load_configuration
    end

    # === CONFIGURATION MANAGEMENT ===

    def load_configuration
      # Start with base index configuration
      base_config = INDEX_BASE_CONFIG[@index_symbol] || INDEX_BASE_CONFIG[:nifty]

      # Merge with index_cfg if available
      base_config = base_config.merge(
        index: @index_symbol,
        symbol: (@index_cfg[:key] || @index_cfg['key']).to_s.upcase,
        exchange_segment: @index_cfg[:segment] || @index_cfg['segment'] || base_config[:exchange_segment],
        lot_size: @index_cfg[:lot] || @index_cfg['lot'] || base_config[:lot_size]
      )

      # Load behavior strategies
      BEHAVIOR_STRATEGIES.each do |strategy_name, strategy_config|
        strategy_key = strategy_config[:method]
        index_specific = strategy_config[:index_specific][@index_symbol]
        default_value = strategy_config[:default]

        # Allow override from algo.yml, then index_specific, then default
        algo_config_key = strategy_name.to_s
        algo_value = AlgoConfig.fetch.dig(:option_chain, algo_config_key.to_sym)

        base_config[strategy_key] = if @custom_config[strategy_key]
                                      @custom_config[strategy_key].merge(default_value)
                                    elsif algo_value
                                      algo_value.is_a?(Hash) ? default_value.merge(algo_value) : default_value
                                    elsif index_specific
                                      default_value.merge(index_specific)
                                    else
                                      default_value.dup
                                    end
      end

      # Merge global option_chain config from algo.yml
      global_config = AlgoConfig.fetch[:option_chain] || {}
      base_config[:min_iv] = global_config[:min_iv] || base_config[:assess_volatility][:min_iv]
      base_config[:max_iv] = global_config[:max_iv] || base_config[:assess_volatility][:max_iv]
      base_config[:min_oi] = global_config[:min_oi] || base_config[:filter_by_liquidity][:min_oi]
      base_config[:max_spread_pct] = global_config[:max_spread_pct] || base_config[:filter_by_liquidity][:max_spread_pct]

      base_config
    end

    # === INSTANCE METHODS (New Configurable API) ===

    # Recommend strikes for a given signal direction
    def recommend_strikes_for_signal(signal, custom_params = {})
      load_chain_data! unless @chain_data

      atm = find_atm_strike
      return { strikes: [], option_type: nil } unless atm && @strike_interval

      # Get strategy configuration
      strategy_config = @config[:select_strikes_for_signal].merge(custom_params)
      offset = strategy_config[:offset]
      include_atm = strategy_config[:include_atm]
      max_otm = strategy_config[:max_otm]

      # Determine target strikes
      if [:bullish, 'BUY', :ce, 'ce'].include?(signal.to_s.downcase.to_sym)
        option_type = 'ce'
        from_strike = include_atm ? atm : atm + @strike_interval
        to_strike = atm + (max_otm * @strike_interval)
        target_strikes = strikes_in_range(from_strike, to_strike, @strike_interval)
      elsif [:bearish, 'SELL', :pe, 'pe'].include?(signal.to_s.downcase.to_sym)
        option_type = 'pe'
        from_strike = include_atm ? atm : atm - @strike_interval
        to_strike = atm - (max_otm * @strike_interval)
        target_strikes = strikes_in_range(to_strike, from_strike, @strike_interval)
      else
        return { strikes: [], option_type: nil }
      end

      # Apply configured filters
      filtered_strikes = filter_by_liquidity(target_strikes, option_type)
      filtered_strikes = filter_by_volatility(filtered_strikes, option_type)
      filtered_strikes = filter_by_delta(filtered_strikes, option_type)

      { strikes: filtered_strikes, option_type: option_type }
    end

    def filter_by_liquidity(strikes, option_type)
      strategy_config = @config[:filter_by_liquidity]

      strikes.select do |strike|
        data = get_strike_data(strike, option_type)
        next false unless data

        # Check all liquidity criteria
        oi = data['oi']&.to_i || 0
        volume = data['volume']&.to_i || 0
        meets_oi = oi >= strategy_config[:min_oi]
        meets_volume = volume >= strategy_config[:min_volume]

        # Check bid-ask spread
        bid = data['top_bid_price']&.to_f || 0
        ask = data['top_ask_price']&.to_f || 0
        spread_pct = bid.positive? ? (ask - bid) / bid : Float::INFINITY
        meets_spread = spread_pct <= strategy_config[:max_spread_pct]

        meets_oi && meets_volume && meets_spread
      end
    end

    def filter_by_volatility(strikes, option_type)
      strategy_config = @config[:assess_volatility]
      min_iv = @config[:min_iv] || strategy_config[:min_iv]
      max_iv = @config[:max_iv] || strategy_config[:max_iv]

      strikes.select do |strike|
        iv = implied_volatility(strike, option_type)
        next false unless iv

        # Check IV range
        iv >= min_iv && iv <= max_iv
      end
    end

    def filter_by_delta(strikes, option_type)
      strategy_config = @config[:filter_by_delta]
      min_delta = if strategy_config[:time_based]
                    min_delta_now
                  else
                    strategy_config[:min_delta]
                  end

      strikes.select do |strike|
        delta = get_delta(strike, option_type)
        next false unless delta

        delta.abs >= min_delta
      end
    end

    def assess_volatility(strike, option_type)
      iv = implied_volatility(strike, option_type)
      return nil unless iv

      strategy_config = @config[:assess_volatility]

      if iv < strategy_config[:low_iv]
        :cheap
      elsif iv > strategy_config[:high_iv]
        :expensive
      else
        :fair
      end
    end

    def calculate_position_size(capital, option_price, custom_params = {})
      strategy_config = @config[:calculate_position_size].merge(custom_params)

      max_risk_amount = capital * strategy_config[:risk_per_trade] / 100.0
      max_capital_amount = capital * strategy_config[:max_capital_utilization]

      # Calculate based on risk
      risk_based_lots = (max_risk_amount / (option_price * @config[:lot_size])).floor

      # Calculate based on capital utilization
      capital_based_lots = (max_capital_amount / (option_price * @config[:lot_size])).floor

      # Take the more conservative (smaller) of the two
      [risk_based_lots, capital_based_lots, 1].max
    end

    def analyze_strike(strike, option_type)
      data = get_strike_data(strike, option_type)
      return nil unless data

      {
        strike: strike,
        option_type: option_type,
        last_price: data['last_price']&.to_f,
        oi: data['oi']&.to_i,
        volume: data['volume']&.to_i,
        iv: data['implied_volatility']&.to_f,
        iv_assessment: assess_volatility(strike, option_type),
        delta: get_delta(strike, option_type),
        greeks: data['greeks'] || {},
        liquidity_status: liquidity_status(strike, option_type),
        bid_ask_spread: calculate_bid_ask_spread(data)
      }
    end

    def liquidity_status(strike, option_type)
      data = get_strike_data(strike, option_type)
      return :unknown unless data

      strategy_config = @config[:filter_by_liquidity]

      oi = data['oi']&.to_i || 0
      volume = data['volume']&.to_i || 0

      if oi >= strategy_config[:min_oi] && volume >= strategy_config[:min_volume]
        :excellent
      elsif oi >= strategy_config[:min_oi] * 0.5 && volume >= strategy_config[:min_volume] * 0.5
        :good
      else
        :poor
      end
    end

    def chain_summary
      load_chain_data! unless @chain_data

      {
        index: @index_symbol,
        symbol: @config[:symbol],
        spot_price: @spot_price,
        strike_interval: @strike_interval,
        total_strikes: @sorted_strikes&.size || 0,
        atm_strike: find_atm_strike,
        config_summary: {
          lot_size: @config[:lot_size],
          point_value: @config[:point_value],
          exchange: @config[:exchange_segment]
        }
      }
    end

    # === BACKWARD COMPATIBILITY METHODS ===

    def select_candidates(limit: 2, direction: DEFAULT_DIRECTION)
      picks = self.class.pick_strikes(
        index_cfg: @index_cfg,
        direction: direction.presence&.to_sym || DEFAULT_DIRECTION
      )
      return [] unless picks.present?

      picks.first([limit.to_i, 1].max).map { |pick| decorate_pick(pick) }
    rescue StandardError => e
      Rails.logger.error("[Options::ChainAnalyzer] select_candidates failed: #{e.class} - #{e.message}")
      []
    end

    # === CLASS METHODS (Backward Compatibility) ===

    class << self
      def pick_strikes(index_cfg:, direction:, ta_context: nil)
        # Log TA context if available (for future use in strike selection logic)
        if ta_context
          Rails.logger.debug do
            "[Options::ChainAnalyzer] TA context available for #{index_cfg[:key]}: " \
            "signal=#{ta_context[:signal]}, confidence=#{ta_context[:confidence]&.round(2)}"
          end
        end

        # Use instance-based approach for consistency
        analyzer = new(
          index: index_cfg,
          data_provider: nil, # Not needed for class method
          config: {}
        )

        # Load chain data
        analyzer.load_chain_data!

        return [] unless analyzer.chain_data&.any? && analyzer.sorted_strikes&.any?

        # Get recommendation using configurable strategy
        recommendation = analyzer.recommend_strikes_for_signal(direction)

        return [] unless recommendation[:strikes]&.any?

        # Convert to legacy format expected by Signal::Engine
        picks = recommendation[:strikes].map do |strike|
          analysis = analyzer.analyze_strike(strike, recommendation[:option_type])
          next unless analysis && analysis[:last_price]&.positive?

          # Find derivative for security_id
          derivative = analyzer.find_derivative(strike, recommendation[:option_type])
          security_id = if derivative&.security_id
                         derived_id = derivative.security_id.to_s
                         valid_security_id?(derived_id) ? derived_id : nil
                       end

          security_id ||= analyzer.find_security_id_fallback(strike, recommendation[:option_type])
          next unless security_id.present?

          # Get derivative segment
          derivative_segment = if derivative&.respond_to?(:exchange_segment) && derivative.exchange_segment.present?
                                 derivative.exchange_segment
                               elsif derivative&.is_a?(Hash)
                                 derivative[:exchange_segment]
                               end
          derivative_segment ||= analyzer.instrument&.exchange_segment if analyzer.instrument&.respond_to?(:exchange_segment)
          derivative_segment ||= analyzer.config[:exchange_segment]

          {
            segment: derivative_segment,
            security_id: security_id,
            symbol: "#{analyzer.config[:symbol]}-#{analyzer.expiry_date&.strftime('%b%Y')}-#{strike.to_i}-#{recommendation[:option_type].upcase}",
            ltp: analysis[:last_price],
            iv: analysis[:iv],
            oi: analysis[:oi],
            spread: analysis[:bid_ask_spread] / [analysis[:last_price], 1].max,
            lot_size: derivative&.lot_size || analyzer.config[:lot_size],
            derivative_id: derivative&.id
          }
        end.compact

        # Return top 2 picks (maintains backward compatibility)
        picks.first(2)
      end

      def valid_security_id?(value)
        id = value.to_s
        return false if id.blank?
        return false if id.start_with?('TEST_')

        true
      end
    end

    # === HELPER METHODS ===

    def load_chain_data!
      return if @chain_data

      # Get cached index instrument
      @instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      unless @instrument
        Rails.logger.warn("[Options::ChainAnalyzer] No instrument found for #{@index_cfg[:key]}")
        return
      end

      # Get expiry list
      expiry_list = @instrument.expiry_list
      unless expiry_list&.any?
        Rails.logger.warn("[Options::ChainAnalyzer] No expiry list available for #{@index_cfg[:key]}")
        return
      end

      # Get the next upcoming expiry
      @expiry_date = find_next_expiry(expiry_list)
      unless @expiry_date
        Rails.logger.warn("[Options::ChainAnalyzer] Could not determine next expiry for #{@index_cfg[:key]}")
        return
      end

      # Fetch option chain
      chain_result = begin
        @instrument.fetch_option_chain(@expiry_date)
      rescue StandardError => e
        Rails.logger.warn("[Options::ChainAnalyzer] Could not fetch option chain: #{e.message}")
        nil
      end

      return unless chain_result

      @chain_data = chain_result[:oc] || chain_result['oc'] || {}
      @spot_price ||= chain_result[:last_price] || chain_result['last_price']&.to_f
      @sorted_strikes = extract_and_sort_strikes
      @strike_interval = calculate_strike_interval
    end

    def extract_and_sort_strikes
      return [] unless @chain_data

      @chain_data.keys.map(&:to_f).sort
    end

    def calculate_strike_interval
      return nil if @sorted_strikes&.size.to_i < 2

      intervals = @sorted_strikes.each_cons(2).map { |a, b| b - a }
      intervals.group_by(&:itself).max_by { |_, v| v.size }&.first || @config[:strike_interval]
    end

    def find_atm_strike
      return nil if @sorted_strikes&.empty? || @spot_price.nil?

      @sorted_strikes.min_by { |strike| (strike - @spot_price).abs }
    end

    def get_strike_data(strike_price, option_type = nil)
      return nil unless @chain_data

      key = sprintf('%.6f', strike_price)
      data = @chain_data[key]

      if option_type
        data&.dig(option_type.downcase)
      else
        data
      end
    end

    def implied_volatility(strike_price, option_type)
      data = get_strike_data(strike_price, option_type)
      data&.dig('implied_volatility')&.to_f
    end

    def get_delta(strike_price, option_type)
      data = get_strike_data(strike_price, option_type)
      data&.dig('greeks', 'delta')&.to_f
    end

    def strikes_in_range(from_strike, to_strike, step = nil)
      step ||= @strike_interval
      return [] unless step && @sorted_strikes

      current = from_strike
      strikes = []

      while (step > 0 ? current <= to_strike : current >= to_strike)
        closest = @sorted_strikes.min_by { |s| (s - current).abs }
        strikes << closest if closest && !strikes.include?(closest)
        current += step
        break if strikes.size >= 10 # Safety limit
      end

      strikes.uniq.sort
    end

    def find_derivative(strike, option_type)
      return nil unless @instrument && @expiry_date

      expiry_date_obj = Date.parse(@expiry_date)
      option_type_upcase = option_type.to_s.upcase

      strike_bd = BigDecimal(strike.to_s)

      derivative_scope = if @instrument.respond_to?(:derivatives) && @instrument.derivatives.present?
                           @instrument.derivatives
                         elsif @instrument.persisted?
                           @instrument.derivatives
                         end

      if derivative_scope
        Array(derivative_scope).detect do |d|
          d.expiry_date == expiry_date_obj &&
            d.option_type == option_type_upcase &&
            BigDecimal(d.strike_price.to_s) == strike_bd
        end
      else
        Derivative.where(
          underlying_symbol: @instrument.symbol_name,
          exchange: @instrument.exchange,
          segment: @instrument.segment,
          expiry_date: expiry_date_obj,
          option_type: option_type_upcase
        ).detect do |d|
          BigDecimal(d.strike_price.to_s) == strike_bd
        end
      end
    end

    def find_security_id_fallback(strike, option_type)
      return nil unless @index_cfg && @expiry_date

      expiry_date_obj = Date.parse(@expiry_date)
      option_type_upcase = option_type.to_s.upcase

      Derivative.find_security_id(
        underlying_symbol: (@index_cfg[:key] || @index_cfg['key']).to_s,
        strike_price: strike,
        expiry_date: expiry_date_obj,
        option_type: option_type_upcase
      )
    end

    def find_next_expiry(expiry_list)
      return nil unless expiry_list.respond_to?(:each)

      today = Time.zone.today

      parsed = expiry_list.compact.filter_map do |raw|
        case raw
        when Date
          raw
        when Time, DateTime, ActiveSupport::TimeWithZone
          raw.to_date
        when String
          begin
            Date.parse(raw)
          rescue ArgumentError
            nil
          end
        end
      end

      next_expiry = parsed.select { |date| date >= today }.min
      next_expiry&.strftime('%Y-%m-%d')
    end

    def min_delta_now
      h = Time.zone.now.hour
      return 0.15 if h >= 14 # After 2 PM - moderate delta for OTM options
      return 0.12 if h >= 13 # After 1 PM - lower delta acceptable
      return 0.10 if h >= 11 # After 11 AM - even lower delta

      0.08 # Before 11 AM - very low delta acceptable for OTM
    end

    def calculate_bid_ask_spread(data)
      bid = data['top_bid_price']&.to_f || 0
      ask = data['top_ask_price']&.to_f || 0
      ask - bid
    end

    private

    def normalize_index(index)
      return index.deep_symbolize_keys if index.respond_to?(:deep_symbolize_keys)

      Array(index).each_with_object({}) do |(k, v), acc|
        acc[k.to_sym] = v
      end
    end

    def decorate_pick(pick)
      pick.merge(
        index_key: @index_cfg[:key],
        underlying_spot: fetch_spot,
        analyzer_config: @custom_config.presence
      ).compact
    end

    def fetch_spot
      return @spot_price if @spot_price

      return unless @provider&.respond_to?(:underlying_spot)

      @provider.underlying_spot(@index_cfg[:key])
    rescue StandardError => e
      Rails.logger.debug { "[Options::ChainAnalyzer] Spot fetch failed: #{e.class} - #{e.message}" }
      nil
    end
  end
end
