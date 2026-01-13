# frozen_string_literal: true

require 'bigdecimal'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'

module Options
  class ChainAnalyzer
    DEFAULT_DIRECTION = :bullish

    # === CONFIGURABLE BEHAVIOR STRATEGIES (Strategy pattern via config) ===
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

    # Load chain data from instrument
    def load_chain_data!
      @instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      unless @instrument
        Rails.logger.warn("[Options::ChainAnalyzer] No instrument found for #{@index_cfg[:key]}")
        return false
      end

      expiry_list = @instrument.expiry_list
      unless expiry_list&.any?
        Rails.logger.warn("[Options::ChainAnalyzer] No expiry list available for #{@index_cfg[:key]}")
        return false
      end

      @expiry_date = self.class.find_next_expiry(expiry_list)
      unless @expiry_date
        Rails.logger.warn("[Options::ChainAnalyzer] Could not determine next expiry for #{@index_cfg[:key]}")
        return false
      end

      chain_data_raw = begin
        @instrument.fetch_option_chain(@expiry_date)
      rescue StandardError => e
        Rails.logger.warn("[Options::ChainAnalyzer] Failed to fetch chain: #{e.class} - #{e.message}")
        nil
      end

      unless chain_data_raw
        Rails.logger.warn("[Options::ChainAnalyzer] No option chain data for #{@index_cfg[:key]} #{@expiry_date}")
        return false
      end

      @chain_data = chain_data_raw
      @spot_price = chain_data_raw[:last_price]&.to_f
      @sorted_strikes = chain_data_raw[:oc]&.keys&.map(&:to_f)&.sort || []

      true
    end

    # Recommend strikes for a given signal direction
    def recommend_strikes_for_signal(signal, options = {})
      return { strikes: [], option_type: nil, error: 'Chain data not loaded' } unless chain_data_loaded?

      direction = signal.to_sym
      option_type = direction == :bullish ? 'ce' : 'pe'

      # Merge runtime options with configured strike selection
      strike_config = @config[:strike_selection].merge(options.slice(:offset, :include_atm, :max_otm))

      # Calculate strike interval
      strike_interval = calculate_strike_interval

      # Find ATM strike
      atm_strike = find_atm_strike(@spot_price, strike_interval)

      # Generate candidate strikes
      candidates = generate_candidate_strikes(atm_strike, strike_interval, option_type, strike_config)

      # Apply filters
      filtered = filter_strikes(candidates, option_type)

      # Sort by score
      scored = score_strikes(filtered, atm_strike, option_type)

      {
        strikes: scored.pluck(:strike),
        option_type: option_type,
        atm_strike: atm_strike,
        spot_price: @spot_price,
        expiry_date: @expiry_date
      }
    end

    # Get chain summary
    def chain_summary
      return nil unless chain_data_loaded?

      {
        index: @index_cfg[:key],
        spot_price: @spot_price,
        expiry_date: @expiry_date,
        total_strikes: @sorted_strikes.size,
        strike_range: @sorted_strikes.any? ? { min: @sorted_strikes.first, max: @sorted_strikes.last } : nil,
        strike_interval: calculate_strike_interval,
        atm_strike: find_atm_strike(@spot_price, calculate_strike_interval),
        timestamp: Time.current
      }
    end

    # Assess volatility for a strike
    def assess_volatility(strike, option_type)
      return nil unless chain_data_loaded?

      option_data = get_option_data(strike, option_type)
      return nil unless option_data

      iv = option_data['implied_volatility']&.to_f
      return nil unless iv

      thresholds = @config[:volatility_assessment]

      if iv < thresholds[:low_iv]
        :cheap
      elsif iv > thresholds[:high_iv]
        :expensive
      else
        :fair
      end
    end

    # Get liquidity status for a strike
    def liquidity_status(strike, option_type)
      return nil unless chain_data_loaded?

      option_data = get_option_data(strike, option_type)
      return nil unless option_data

      oi = option_data['oi'].to_i
      volume = option_data['volume'].to_i
      bid = option_data['top_bid_price']&.to_f
      ask = option_data['top_ask_price']&.to_f

      spread_pct = (((ask - bid) / bid) * 100 if bid && ask && bid.positive?)

      thresholds = @config[:liquidity_filter]

      {
        oi: oi,
        volume: volume,
        spread_pct: spread_pct,
        meets_oi_threshold: oi >= thresholds[:min_oi],
        meets_volume_threshold: volume >= thresholds[:min_volume],
        meets_spread_threshold: spread_pct.nil? || spread_pct <= thresholds[:max_spread_pct],
        overall_liquidity: calculate_liquidity_score(oi, volume, spread_pct)
      }
    end

    # Analyze a specific strike
    def analyze_strike(strike, option_type)
      return nil unless chain_data_loaded?

      option_data = get_option_data(strike, option_type)
      return nil unless option_data

      greeks = option_data['greeks'] || {}
      strike_interval = calculate_strike_interval
      atm_strike = find_atm_strike(@spot_price, strike_interval)

      {
        strike: strike,
        option_type: option_type,
        last_price: option_data['last_price']&.to_f,
        iv: option_data['implied_volatility']&.to_f,
        oi: option_data['oi']&.to_i,
        volume: option_data['volume']&.to_i,
        bid: option_data['top_bid_price']&.to_f,
        ask: option_data['top_ask_price']&.to_f,
        delta: greeks['delta']&.to_f,
        gamma: greeks['gamma']&.to_f,
        theta: greeks['theta']&.to_f,
        vega: greeks['vega']&.to_f,
        distance_from_atm: (strike - atm_strike).abs,
        strike_type: classify_strike(strike, atm_strike, strike_interval, option_type),
        volatility_assessment: assess_volatility(strike, option_type),
        liquidity_status: liquidity_status(strike, option_type)
      }
    end

    # Calculate position size
    def calculate_position_size(capital, option_price, risk_params = {})
      return 0 unless capital&.positive? && option_price&.positive?

      params = @config[:position_sizing].merge(risk_params)
      risk_amount = capital * params[:risk_per_trade]
      max_capital_used = capital * params[:max_capital_utilization]

      # Calculate lots based on risk
      lots_by_risk = (risk_amount / option_price).floor

      # Calculate lots based on max capital utilization
      lots_by_capital = (max_capital_used / option_price).floor

      # Use the smaller of the two
      [lots_by_risk, lots_by_capital].min
    end

    # Backward compatible method
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
      # Start with algo.yml config
      algo_config = AlgoConfig.fetch[:option_chain] || {}

      # Load behavior strategies
      config = {}
      BEHAVIOR_STRATEGIES.each_value do |strategy_config|
        strategy_key = strategy_config[:method]
        index_specific = strategy_config[:index_specific][@index_symbol]
        default_value = strategy_config[:default]

        # Priority: custom_config > index_specific > default > algo.yml
        config[strategy_key] = (@custom_config[strategy_key] ||
                                 index_specific ||
                                 default_value ||
                                 algo_config).dup
      end

      # Add convenience accessors
      config[:strike_selection] = config[:configure_strike_selection]
      config[:liquidity_filter] = config[:configure_liquidity_filter]
      config[:volatility_assessment] = config[:configure_volatility_assessment]
      config[:position_sizing] = config[:configure_position_sizing]
      config[:delta_filter] = config[:configure_delta_filter]

      # Add index-specific metadata
      config[:lot_size] = @index_cfg[:lot]&.to_i || 50
      config[:point_value] = @index_cfg[:point_value]&.to_f || 25.0

      config
    end

    def chain_data_loaded?
      @chain_data.present? && @sorted_strikes&.any?
    end

    def calculate_strike_interval
      return 50 unless @sorted_strikes&.size&.>= 2

      @sorted_strikes[1] - @sorted_strikes[0]
    end

    def find_atm_strike(spot, interval)
      return spot unless interval&.positive?

      (spot / interval).round * interval
    end

    def generate_candidate_strikes(atm_strike, interval, option_type, strike_config)
      strike_config[:offset] || 2
      include_atm = strike_config[:include_atm] != false
      max_otm = strike_config[:max_otm] || 2

      candidates = []

      candidates << atm_strike if include_atm && @sorted_strikes.include?(atm_strike)

      if option_type == 'ce'
        # CE: ATM+1, ATM+2, etc. (OTM calls)
        1.upto(max_otm) do |i|
          strike = atm_strike + (i * interval)
          candidates << strike if @sorted_strikes.include?(strike)
        end
      else
        # PE: ATM-1, ATM-2, etc. (OTM puts)
        1.upto(max_otm) do |i|
          strike = atm_strike - (i * interval)
          candidates << strike if @sorted_strikes.include?(strike)
        end
      end

      candidates.uniq.sort
    end

    def filter_strikes(candidates, option_type)
      candidates.filter_map do |strike|
        option_data = get_option_data(strike, option_type)
        next nil unless option_data

        # Apply filters
        next nil unless passes_liquidity_filter?(option_data)
        next nil unless passes_volatility_filter?(option_data, strike)
        next nil unless passes_delta_filter?(option_data)

        {
          strike: strike,
          option_data: option_data
        }
      end
    end

    def passes_liquidity_filter?(option_data)
      thresholds = @config[:liquidity_filter]
      oi = option_data['oi'].to_i
      volume = option_data['volume'].to_i
      bid = option_data['top_bid_price']&.to_f
      ask = option_data['top_ask_price']&.to_f

      return false unless oi >= thresholds[:min_oi]
      return false unless volume >= thresholds[:min_volume]

      if bid && ask && bid.positive?
        spread_pct = ((ask - bid) / bid) * 100
        return false if spread_pct > thresholds[:max_spread_pct]
      end

      true
    end

    def passes_volatility_filter?(option_data, strike)
      thresholds = @config[:volatility_assessment]
      iv = option_data['implied_volatility']&.to_f
      return false unless iv

      # Relaxed thresholds for ATM strikes
      strike_interval = calculate_strike_interval
      atm_strike = find_atm_strike(@spot_price, strike_interval)

      min_iv_threshold = if strike == atm_strike
                           [5.0, thresholds[:min_iv] * 0.6].max
                         elsif (strike - atm_strike).abs <= strike_interval
                           [7.0, thresholds[:min_iv] * 0.8].max
                         else
                           thresholds[:min_iv]
                         end

      iv.between?(min_iv_threshold, thresholds[:max_iv])
    end

    def passes_delta_filter?(option_data)
      thresholds = @config[:delta_filter]
      greeks = option_data['greeks'] || {}
      delta = greeks['delta']&.to_f&.abs

      return false unless delta

      min_delta = if thresholds[:time_based]
                    self.class.min_delta_now
                  else
                    thresholds[:min_delta]
                  end

      delta >= min_delta
    end

    def score_strikes(filtered, atm_strike, option_type)
      calculate_strike_interval
      iv_rank = 0.5 # Default - could be calculated from historical IV
      atm_range_percent = self.class.atm_range_pct(iv_rank)

      filtered.map do |item|
        strike = item[:strike]
        option_data = item[:option_data]

        leg = {
          strike: strike,
          ltp: option_data['last_price']&.to_f,
          iv: option_data['implied_volatility']&.to_f,
          oi: option_data['oi']&.to_i,
          spread: calculate_spread_ratio(option_data),
          delta: option_data.dig('greeks', 'delta')&.to_f&.abs,
          distance_from_atm: (strike - atm_strike).abs
        }

        score = self.class.calculate_strike_score(leg, option_type.to_sym, atm_strike, atm_range_percent)
        leg.merge(score: score)
      end.sort_by { |leg| [-leg[:score], leg[:distance_from_atm]] }
    end

    def calculate_spread_ratio(option_data)
      bid = option_data['top_bid_price']&.to_f
      ask = option_data['top_ask_price']&.to_f

      return nil unless bid && ask && bid.positive?

      (ask - bid) / bid
    end

    def get_option_data(strike, option_type)
      return nil unless @chain_data && @chain_data[:oc]

      strike_data = @chain_data[:oc][strike.to_s]
      return nil unless strike_data

      strike_data[option_type]
    end

    def classify_strike(strike, atm_strike, interval, option_type)
      return 'ATM' if strike == atm_strike

      if option_type == 'ce'
        diff = (strike - atm_strike) / interval
        case diff
        when 1 then 'ATM+1'
        when 2 then 'ATM+2'
        when 3 then 'ATM+3'
        else diff.positive? ? "OTM+#{diff.to_i}" : "ITM#{diff.to_i}"
        end
      else
        diff = (atm_strike - strike) / interval
        case diff
        when 1 then 'ATM-1'
        when 2 then 'ATM-2'
        when 3 then 'ATM-3'
        else diff.positive? ? "OTM-#{diff.to_i}" : "ITM+#{diff.to_i}"
        end
      end
    end

    def calculate_liquidity_score(oi, _volume, spread_pct)
      score = 0

      # OI contribution (0-50)
      score += if oi >= 1_000_000
                 50
               elsif oi >= 500_000
                 40
               elsif oi >= 100_000
                 30
               else
                 20
               end

      # Spread penalty
      if spread_pct
        if spread_pct > 2.0
          score *= 0.8
        elsif spread_pct > 1.0
          score *= 0.9
        end
      end

      score
    end

    def decorate_pick(pick)
      pick.merge(
        index_key: @index_cfg[:key],
        underlying_spot: fetch_spot,
        analyzer_config: @config.presence
      ).compact
    end

    def fetch_spot
      return @spot_price if @spot_price

      return unless @provider.respond_to?(:underlying_spot)

      @provider.underlying_spot(@index_cfg[:key])
    rescue StandardError => e
      Rails.logger.debug { "[Options::ChainAnalyzer] Spot fetch failed: #{e.class} - #{e.message}" }
      nil
    end

    # Class methods (backward compatible)
    class << self
      def pick_strikes(index_cfg:, direction:)
        # Rails.logger.info("[Options] Starting strike selection for #{index_cfg[:key]} #{direction}")

        # Get cached index instrument
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.warn("[Options] No instrument found for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        # Rails.logger.debug { "[Options] Using instrument: #{instrument.symbol_name}" }

        # Use instrument's existing methods to get expiry list and option chain
        expiry_list = instrument.expiry_list
        unless expiry_list&.any?
          Rails.logger.warn("[Options] No expiry list available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        # Rails.logger.debug { "[Options] Available expiries: #{expiry_list}" }

        # Get the next upcoming expiry
        expiry_date = find_next_expiry(expiry_list)
        unless expiry_date
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        # Rails.logger.info("[Options] Using expiry: #{expiry_date}")

        # Fetch option chain using instrument's method
        chain_data = begin
          instrument.fetch_option_chain(expiry_date)
        rescue StandardError => e
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]} #{expiry_date}: #{e.message}") if defined?(Rails)
          nil
        end
        unless chain_data
          Rails.logger.warn("[Options] No option chain data for #{index_cfg[:key]} #{expiry_date}") if defined?(Rails)
          return []
        end

        # Rails.logger.debug { "[Options] Chain data structure: #{chain_data.keys}" }
        # Rails.logger.debug { "[Options] OC data size: #{chain_data[:oc]&.size || 'nil'}" }

        # Debug: Show sample of raw option data
        if chain_data[:oc]&.any?
          sample_strike = chain_data[:oc].keys.first
          chain_data[:oc][sample_strike]
          # Rails.logger.debug { "[Options] Sample strike #{sample_strike} data: #{sample_data}" }
          # Rails.logger.debug { "[Options] Sample PE data: #{sample_data['pe']}" } if sample_data['pe']
        end

        atm_price = chain_data[:last_price]
        unless atm_price
          Rails.logger.warn("[Options] No ATM price available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        # Rails.logger.info("[Options] ATM price: #{atm_price}")

        side = direction == :bullish ? :ce : :pe
        # For buying options, focus on ATM and ATM+1 strikes only
        # This prevents selecting expensive ITM options
        # Rails.logger.debug { "[Options] Looking for #{side} options at ATM and ATM#{[:ce, 'ce'].include?(side) ? '+1' : '-1'} strikes only" }

        legs = filter_and_rank_from_instrument_data(chain_data[:oc], atm: atm_price, side: side, index_cfg: index_cfg,
                                                                     expiry_date: expiry_date, instrument: instrument)
        # Rails.logger.info("[Options] Found #{legs.size} qualifying #{side} options for #{index_cfg[:key]}")

        if legs.any?
          # Rails.logger.info("[Options] Top picks: #{legs.first(2).map { |l| "#{l[:symbol]}@#{l[:strike]} (Score:#{l[:score]&.round(1)}, IV:#{l[:iv]}, OI:#{l[:oi]})" }.join(', ')}")
        end

        legs.first(2).map do |leg|
          leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread, :lot_size, :derivative_id)
        end
      end

      # Strike Qualification Layer (context-aware + expected-move hard gate)
      #
      # IMPORTANT:
      # - This is additive and does NOT change existing pick_strikes behavior.
      # - If qualification fails, it returns [] to HARD-BLOCK entry.
      #
      # @param index_cfg [Hash] Index configuration
      # @param direction [Symbol] :bullish or :bearish
      # @param permission [Symbol] :execution_only, :scale_ready, :full_deploy
      # @param expected_spot_move [Float] Expected spot move in points (ATR-derived)
      # @return [Array<Hash>] Array with a single qualified pick, or [] if blocked
      def pick_strikes_with_qualification(index_cfg:, direction:, permission:, expected_spot_move:)
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.warn("[Options] No instrument found for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        expiry_list = instrument.expiry_list
        unless expiry_list&.any?
          Rails.logger.warn("[Options] No expiry list available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        expiry_date = find_next_expiry(expiry_list)
        unless expiry_date
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        chain_data = begin
          instrument.fetch_option_chain(expiry_date)
        rescue StandardError => e
          if defined?(Rails)
            Rails.logger.warn(
              "[Options] Could not fetch option chain for #{index_cfg[:key]} #{expiry_date}: #{e.class} - #{e.message}"
            )
          end
          nil
        end

        unless chain_data && chain_data[:oc].is_a?(Hash)
          if defined?(Rails)
            Rails.logger.warn(
              "[Options] No option chain data for #{index_cfg[:key]} #{expiry_date} " \
              "(chain_data: #{chain_data.present? ? 'present but invalid' : 'nil'})"
            )
          end
          return []
        end

        # Log chain data availability for debugging
        if chain_data[:oc].empty?
          Rails.logger.warn("[Options] Option chain for #{index_cfg[:key]} #{expiry_date} is empty")
          return []
        end

        spot = chain_data[:last_price]&.to_f
        unless spot&.positive?
          Rails.logger.warn("[Options] No SPOT/last_price available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        normalized_permission = permission.to_s.downcase.to_sym
        expected_move = expected_spot_move.to_f
        unless expected_move.positive?
          Rails.logger.info("[Options] Expected move unavailable -> BLOCK #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        side_sym = direction == :bullish ? :CE : :PE
        oc_side = direction == :bullish ? :ce : :pe

        # Filter option chain to only include strikes that exist in database
        # This ensures we only select strikes that have derivatives synced
        expiry_date_obj = Date.parse(expiry_date)
        option_type = side_sym.to_s

        # Get all available strikes from database for this expiry and option type
        available_strikes_bd = instrument.derivatives.where(
          expiry_date: expiry_date_obj,
          option_type: option_type
        ).pluck(:strike_price).map { |sp| BigDecimal(sp.to_s) }.to_set

        # Filter option chain to only include strikes that exist in database
        filtered_chain = chain_data[:oc].select do |strike_key, _strike_data|
          strike_float = strike_key.to_f
          strike_bd = BigDecimal(strike_float.to_s)
          available_strikes_bd.include?(strike_bd)
        end

        if filtered_chain.empty?
          Rails.logger.warn(
            "[Options] No option chain strikes match database derivatives for #{index_cfg[:key]} " \
            "expiry=#{expiry_date}, option_type=#{option_type}. " \
            "Chain has #{chain_data[:oc].size} strikes, DB has #{available_strikes_bd.size} derivatives. " \
            "Available DB strikes: #{available_strikes_bd.to_a.map(&:to_f).sort.first(10).inspect}"
          ) if defined?(Rails)
          return []
        end

        if filtered_chain.size < chain_data[:oc].size
          Rails.logger.debug(
            "[Options] Filtered option chain: #{chain_data[:oc].size} -> #{filtered_chain.size} strikes " \
            "(only strikes with DB derivatives) for #{index_cfg[:key]}"
          ) if defined?(Rails)
        end

        selector = Options::StrikeQualification::StrikeSelector.new
        selection = selector.call(
          index_key: index_cfg[:key],
          side: side_sym,
          permission: normalized_permission,
          spot: spot,
          option_chain: filtered_chain,
          trend: direction
        )

        unless selection[:ok]
          if defined?(Rails)
            Rails.logger.info(
              "[Options] StrikeSelector BLOCKED #{index_cfg[:key]}: #{selection[:reason]}"
            )
          end
          return []
        end

        # Try selected strike first, then fallback to ATM only.
        legs = filter_and_rank_from_instrument_data(
          chain_data[:oc],
          atm: spot,
          side: oc_side,
          index_cfg: index_cfg,
          expiry_date: expiry_date,
          instrument: instrument,
          target_strikes: [selection[:strike].to_f]
        )

        used_strike_type = selection[:strike_type]

        if legs.blank? && selection[:strike_type] != :ATM
          if defined?(Rails)
            Rails.logger.debug do
              "[Options] Selected strike #{selection[:strike]} (#{selection[:strike_type]}) not found, " \
                "falling back to ATM #{selection[:atm_strike]} for #{index_cfg[:key]}"
            end
          end
          legs = filter_and_rank_from_instrument_data(
            chain_data[:oc],
            atm: spot,
            side: oc_side,
            index_cfg: index_cfg,
            expiry_date: expiry_date,
            instrument: instrument,
            target_strikes: [selection[:atm_strike].to_f]
          )
          used_strike_type = :ATM
        end

        if legs.blank?
          if defined?(Rails)
            Rails.logger.warn(
              "[Options] No legs found after filtering for #{index_cfg[:key]} " \
              "(strike: #{selection[:strike]}, type: #{used_strike_type}, side: #{oc_side})"
            )
          end
          return []
        end

        leg = legs.first
        pick = leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread, :lot_size, :derivative_id, :strike)
                  .merge(strike_type: used_strike_type)

        validator = Options::StrikeQualification::ExpectedMoveValidator.new
        validation = validator.call(
          index_key: index_cfg[:key],
          strike_type: used_strike_type,
          permission: normalized_permission,
          expected_spot_move: expected_move,
          option_ltp: pick[:ltp]
        )

        unless validation[:ok]
          if defined?(Rails)
            Rails.logger.info(
              "[Options] ExpectedMoveValidator BLOCKED #{index_cfg[:key]}: #{validation[:reason]}"
            )
          end
          return []
        end

        [pick]
      rescue StandardError => e
        Rails.logger.error("[Options] pick_strikes_with_qualification failed: #{e.class} - #{e.message}") if defined?(Rails)
        []
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

      def filter_and_rank_from_instrument_data(option_chain_data, atm:, side:, index_cfg:, expiry_date:, instrument:,
                                               target_strikes: nil)
        # Force reload - debugging index_cfg scope issue
        return [] unless option_chain_data

        # Rails.logger.debug { "[Options] Method called with index_cfg: #{index_cfg[:key]}, expiry_date: #{expiry_date}" }

        # Rails.logger.debug { "[Options] Processing #{option_chain_data.size} strikes for #{side} options" }

        # Calculate strike interval dynamically from available strikes
        strikes = option_chain_data.keys.map(&:to_f).sort

        strike_interval = if strikes.size >= 2
                            strikes[1] - strikes[0]
                          else
                            50 # fallback
                          end

        atm_strike = (atm / strike_interval).round * strike_interval

        # Calculate dynamic ATM range based on volatility
        # For now, we'll use a default IV rank of 0.5 (medium volatility)
        # TODO: Integrate with actual IV rank calculation
        iv_rank = 0.5 # Default to medium volatility
        atm_range_percent = atm_range_pct(iv_rank)

        # Rails.logger.debug { "[Options] SPOT: #{atm}, Strike interval: #{strike_interval}, ATM strike: #{atm_strike}" }
        # Rails.logger.debug { "[Options] IV Rank: #{iv_rank}, ATM range: #{atm_range_percent * 100}% (#{atm_range_points.round(2)} points)" }

        # For buying options, focus on ATM and nearby strikes only (ATM, 1OTM, 2OTM max)
        # This prevents selecting expensive ITM options or far OTM options
        computed_target_strikes = if [:ce, 'ce'].include?(side)
                                    # CE: ATM, ATM+1, ATM+2 (OTM calls, max 2OTM)
                                    [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval)]
                                  else
                                    # PE: ATM, ATM-1, ATM-2 (OTM puts, max 2OTM)
                                    [atm_strike, atm_strike - strike_interval, atm_strike - (2 * strike_interval)]
                                  end
        available_strikes = option_chain_data.keys.map(&:to_f)
        target_strikes = (target_strikes.presence || computed_target_strikes).map(&:to_f)
        target_strikes = target_strikes.select { |s| available_strikes.include?(s) }

        # Rails.logger.debug { "[Options] Target strikes for #{side}: #{target_strikes}" }

        # Log strike selection guidance
        log_strike_selection_guidance(side, atm, atm_strike, target_strikes, iv_rank, atm_range_percent,
                                      strike_interval)

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        min_delta = min_delta_now
        # Rails.logger.debug { "[Options] Filter criteria: IV(#{min_iv}-#{max_iv}), OI(>=#{min_oi}), Spread(<=#{max_spread_pct}%), Delta(>=#{min_delta})" }

        legs = []
        rejected_count = 0

        option_chain_data.each do |strike_str, strike_data|
          strike = strike_str.to_f

          # For buying options, only consider target strikes (ATM±1 based on direction)
          # This prevents selecting expensive ITM options
          unless target_strikes.include?(strike)
            rejected_count += 1
            next
          end

          option_data = strike_data[side.to_s]
          unless option_data
            rejected_count += 1
            next
          end

          # Debug: Show available fields for first few strikes
          # Rails.logger.debug { "[Options] Available fields for #{side}: #{option_data.keys}" } if rejected_count < 3

          ltp = option_data['last_price']&.to_f
          iv = option_data['implied_volatility']&.to_f
          oi = option_data['oi']&.to_i
          bid = option_data['top_bid_price']&.to_f
          ask = option_data['top_ask_price']&.to_f

          # Debug: strike label calculation (currently unused)
          _strike_label = if strike == atm_strike
                            'ATM'
                          elsif [:ce, 'ce'].include?(side)
                            strike_diff = (strike - atm_strike) / strike_interval
                            case strike_diff
                            when 1
                              'ATM+1'
                            when 2
                              'ATM+2'
                            else
                              strike_diff == 3 ? 'ATM+3' : 'OTHER'
                            end
                          else
                            strike_diff = (atm_strike - strike) / strike_interval
                            case strike_diff
                            when 1
                              'ATM-1'
                            when 2
                              'ATM-2'
                            else
                              strike_diff == 3 ? 'ATM-3' : 'OTHER'
                            end
                          end
          # Rails.logger.debug { "[Options] Strike #{strike} (#{strike_type}): LTP=#{ltp}, IV=#{iv}, OI=#{oi}, Bid=#{bid}, Ask=#{ask}" }

          # Check LTP
          unless ltp&.positive?
            rejected_count += 1
            # Rails.logger.debug { "[Options] Rejected #{strike}: Invalid LTP" }
            next
          end

          # Check IV with relaxed thresholds for ATM and ATM-1 strikes
          # ATM strikes often have lower IV but are critical for trade entry
          iv_threshold = if strike == atm_strike
                           # ATM: Allow lower IV (minimum 5% instead of default min_iv)
                           [5.0, min_iv * 0.6].max
                         elsif (strike - atm_strike).abs <= strike_interval
                           # ATM±1: Slightly relaxed IV threshold (80% of min_iv)
                           [7.0, min_iv * 0.8].max
                         else
                           # ATM-2 and beyond: Use strict IV threshold
                           min_iv
                         end

          unless iv && iv >= iv_threshold && iv <= max_iv
            rejected_count += 1
            # Rails.logger.debug { "[Options] Rejected #{strike}: IV #{iv} not in range #{iv_threshold.round(2)}-#{max_iv} (relaxed for #{strike_type}: #{iv_threshold.round(2)})" }
            next
          end

          # Check OI
          unless oi && oi >= min_oi
            rejected_count += 1
            # Rails.logger.debug { "[Options] Rejected #{strike}: OI #{oi} < #{min_oi}" }
            next
          end

          # Calculate spread percentage
          spread_ratio = nil
          if bid && ask && bid.positive?
            spread_ratio = (ask - bid) / bid
            spread_pct = spread_ratio * 100
            if spread_pct > max_spread_pct
              rejected_count += 1
              # Rails.logger.debug { "[Options] Rejected #{strike}: Spread #{spread_pct}% > #{max_spread_pct}%" }
              next
            end
          end

          # Check Delta (time-based thresholds)
          delta = option_data.dig('greeks', 'delta')&.to_f&.abs
          unless delta && delta >= min_delta
            rejected_count += 1
            # Rails.logger.debug { "[Options] Rejected #{strike}: Delta #{delta} < #{min_delta}" }
            next
          end

          # Find the derivative security ID using instrument.derivatives association
          # Filter by strike, expiry date, and option type
          expiry_date_obj = Date.parse(expiry_date)
          option_type = side.to_s.upcase # CE or PE

          # Use BigDecimal for accurate float comparison
          strike_bd = BigDecimal(strike.to_s)

          # Try to find derivative using instrument.derivatives association first
          derivative = if instrument.respond_to?(:derivatives)
                         instrument.derivatives.where(
                           expiry_date: expiry_date_obj,
                           option_type: option_type
                         ).detect do |d|
                           BigDecimal(d.strike_price.to_s) == strike_bd
                         end
                       end

          # Fallback: Query by instrument_id if association lookup failed
          derivative ||= Derivative.where(
            instrument_id: instrument.id,
            expiry_date: expiry_date_obj,
            option_type: option_type
          ).detect do |d|
            BigDecimal(d.strike_price.to_s) == strike_bd
          end

          # Second fallback: Query by underlying_symbol, exchange, segment if instrument_id not available
          derivative ||= Derivative.where(
            underlying_symbol: instrument.symbol_name,
            exchange: instrument.exchange,
            segment: instrument.segment,
            expiry_date: expiry_date_obj,
            option_type: option_type
          ).detect do |d|
            BigDecimal(d.strike_price.to_s) == strike_bd
          end

          # Third fallback: Use Derivative.find_by_params (uses underlying_symbol)
          derivative ||= Derivative.find_by_params(
            underlying_symbol: index_cfg[:key],
            strike_price: strike,
            expiry_date: expiry_date_obj,
            option_type: option_type
          )

          if derivative.nil?
            # Log available strikes for debugging
            available_strikes = instrument.derivatives.where(
              expiry_date: expiry_date_obj,
              option_type: option_type
            ).pluck(:strike_price).map(&:to_f).sort

            Rails.logger.debug do
              "[Options::ChainAnalyzer] Derivative not found for #{index_cfg[:key]} " \
                "strike=#{strike}, expiry=#{expiry_date_obj}, option_type=#{option_type}, " \
                "instrument_id=#{instrument.id}, symbol=#{instrument.symbol_name}. " \
                "Available strikes (#{available_strikes.size}): " \
                "#{available_strikes.first(5).join(', ')}#{'...' if available_strikes.size > 5}"
            end
            rejected_count += 1
            next
          end

          security_id = derivative.security_id.to_s
          unless valid_security_id?(security_id)
            Rails.logger.debug do
              "[Options::ChainAnalyzer] Invalid security_id for #{index_cfg[:key]} #{strike} #{side}: " \
                "#{security_id.inspect} (derivative_id=#{derivative.id})"
            end
            rejected_count += 1
            next
          end

          # Verify the derivative matches the strike, expiry, and option type
          derivative_strike_bd = BigDecimal(derivative.strike_price.to_s)
          unless derivative_strike_bd == strike_bd
            Rails.logger.warn do
              "[Options::ChainAnalyzer] Derivative strike mismatch for #{index_cfg[:key]}: " \
                "expected=#{strike_bd}, found=#{derivative_strike_bd} " \
                "(derivative_id=#{derivative.id}, security_id=#{security_id})"
            end
            rejected_count += 1
            next
          end

          unless derivative.expiry_date == expiry_date_obj
            Rails.logger.warn do
              "[Options::ChainAnalyzer] Derivative expiry mismatch for #{index_cfg[:key]}: " \
                "expected=#{expiry_date_obj}, found=#{derivative.expiry_date} " \
                "(derivative_id=#{derivative.id}, security_id=#{security_id})"
            end
            rejected_count += 1
            next
          end

          unless derivative.option_type == option_type
            Rails.logger.warn do
              "[Options::ChainAnalyzer] Derivative option_type mismatch for #{index_cfg[:key]}: " \
                "expected=#{option_type}, found=#{derivative.option_type} " \
                "(derivative_id=#{derivative.id}, security_id=#{security_id})"
            end
            rejected_count += 1
            next
          end

          derivative_segment = if derivative.respond_to?(:exchange_segment) && derivative.exchange_segment.present?
                                 derivative.exchange_segment
                               elsif derivative.is_a?(Hash)
                                 derivative[:exchange_segment]
                               end
          derivative_segment ||= instrument.exchange_segment if instrument.respond_to?(:exchange_segment)
          derivative_segment ||= index_cfg[:segment]

          legs << {
            segment: derivative_segment,
            security_id: security_id,
            symbol: "#{index_cfg[:key]}-#{expiry_date_obj.strftime('%b%Y')}-#{strike.to_i}-#{side.to_s.upcase}",
            strike: strike,
            ltp: ltp,
            iv: iv,
            oi: oi,
            spread: spread_ratio,
            delta: delta,
            distance_from_atm: (strike - atm).abs,
            lot_size: derivative&.lot_size || index_cfg[:lot].to_i,
            derivative_id: derivative&.id
          }

          # Rails.logger.debug { "[Options] Accepted #{strike}: #{legs.last[:symbol]}" }
        end

        # Rails.logger.info("[Options] Filter results: #{legs.size} accepted, #{rejected_count} rejected")

        # Log detailed filtering summary
        log_filtering_summary(side, legs.size, rejected_count, min_iv, max_iv, min_oi, max_spread_pct, min_delta)

        # Apply sophisticated scoring system
        scored_legs = legs.map do |leg|
          score = calculate_strike_score(leg, side, atm_strike, atm_range_percent)
          leg.merge(score: score)
        end

        # Sort by score (descending), then by distance from ATM
        scored_legs.sort_by { |leg| [-leg[:score], leg[:distance_from_atm]] }
      end

      def filter_and_rank(legs, atm:, side:, window:)
        return [] unless legs

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        legs.select do |leg|
          leg[:type] == side &&
            (leg[:strike].to_f - atm.to_f).abs <= window &&
            leg[:iv].to_f.between?(min_iv, max_iv) &&
            leg[:oi].to_i >= min_oi &&
            leg.fetch(:spread_pct, 0.0).to_f <= max_spread_pct
        end.sort_by { |leg| [-leg[:oi].to_i, leg.fetch(:spread_pct, 0.0).to_f] }
      end

      # Dynamic minimum delta thresholds depending on time of day
      # More realistic delta requirements for OTM options
      def min_delta_now
        h = Time.zone.now.hour
        return 0.15 if h >= 14  # After 2 PM - moderate delta for OTM options
        return 0.12 if h >= 13  # After 1 PM - lower delta acceptable
        return 0.10 if h >= 11  # After 11 AM - even lower delta

        0.08                    # Before 11 AM - very low delta acceptable for OTM
      end

      def valid_security_id?(value)
        id = value.to_s
        return false if id.blank?
        return false if id.start_with?('TEST_')

        true
      end

      # Dynamic ATM range based on volatility (IV rank)
      # Low volatility = tight range, High volatility = wider range
      def atm_range_pct(iv_rank = 0.5)
        case iv_rank
        when 0.0..0.2 then 0.01 # Low volatility - tight range (1%)
        when 0.2..0.5 then 0.015 # Medium volatility - medium range (1.5%)
        else 0.025               # High volatility - wider range (2.5%)
        end
      end

      # Log comprehensive strike selection guidance
      def log_strike_selection_guidance(side, spot, atm_strike, target_strikes, iv_rank, _atm_range_percent,
                                        strike_interval)
        # Debug: IV rank and strike guidance (currently unused, logging commented out)
        _iv_rank_label = case iv_rank
                         when 0.0..0.2 then 'Low'
                         when 0.2..0.5 then 'Medium'
                         else 'High'
                         end

        _strike_guidance = if [:ce, 'ce'].include?(side)
                             'CE strikes: ATM, ATM+1, ATM+2, ATM+3 (OTM calls only)'
                           else
                             'PE strikes: ATM, ATM-1, ATM-2, ATM-3 (OTM puts only)'
                           end

        # Rails.logger.info('[Options] Strike Selection Guidance:')
        # Rails.logger.info("  - Current SPOT: #{spot}")
        # Rails.logger.info("  - ATM Strike: #{atm_strike}")
        # Rails.logger.info("  - Volatility Regime: #{volatility_regime} (IV Rank: #{iv_rank})")
        # Rails.logger.info("  - ATM Range: #{atm_range_percent * 100}%")
        # Rails.logger.info("  - Target Strikes: #{target_strikes}")
        # Rails.logger.info("  - Strategy: #{explanation}")

        # Log strike analysis
        target_strikes.each_with_index do |strike, _index|
          (strike - atm_strike).abs
          (strike - spot).abs
          if strike == atm_strike
            'ATM'
          elsif [:ce, 'ce'].include?(side)
            strike_diff = (strike - atm_strike) / strike_interval
            case strike_diff
            when 1
              'ATM+1'
            when 2
              'ATM+2'
            else
              strike_diff == 3 ? 'ATM+3' : 'OTHER'
            end
          else
            strike_diff = (atm_strike - strike) / strike_interval
            case strike_diff
            when 1
              'ATM-1'
            when 2
              'ATM-2'
            else
              strike_diff == 3 ? 'ATM-3' : 'OTHER'
            end
          end

          # Rails.logger.info("  - Strike #{index + 1}: #{strike} (#{strike_step}) - #{distance_from_atm} points from ATM, #{distance_from_spot.round(2)} points from spot")
        end
      end

      # Calculate sophisticated strike score based on multiple factors
      def calculate_strike_score(leg, side, atm_strike, atm_range_percent)
        strike_price = leg[:strike]
        ltp = leg[:ltp]
        iv = leg[:iv]
        oi = leg[:oi]

        # Calculate spread percentage from spread and LTP
        spread_pct = if leg[:spread]
                       leg[:spread] * 100
                     else
                       0.0 # Default to 0% spread if not available
                     end

        delta = leg[:delta] || 0.5 # Default delta if not available

        # 1. ATM Preference Score (0-100)
        distance_from_atm = (strike_price - atm_strike).abs
        atm_range_points = atm_strike * atm_range_percent

        atm_preference_score = if distance_from_atm <= (atm_range_points * 0.1)
                                 100 # Perfect ATM
                               elsif distance_from_atm <= (atm_range_points * 0.3)
                                 80  # Near ATM
                               elsif distance_from_atm <= (atm_range_points * 0.6)
                                 50  # Slightly away
                               else
                                 20  # Far from ATM
                               end

        # Penalty for ITM strikes (30% reduction)
        atm_preference_score *= 0.7 if itm_strike?(strike_price, side, atm_strike)

        # 2. Liquidity Score (0-50)
        # Based on OI and spread
        liquidity_score = if oi >= 1_000_000
                            50 # Excellent liquidity
                          elsif oi >= 500_000
                            40  # Good liquidity
                          elsif oi >= 100_000
                            30  # Decent liquidity
                          else
                            20  # Poor liquidity
                          end

        # Spread penalty
        if spread_pct > 2.0
          liquidity_score *= 0.8  # 20% penalty for wide spreads
        elsif spread_pct > 1.0
          liquidity_score *= 0.9  # 10% penalty for moderate spreads
        end

        # 3. Delta Score (0-30)
        # Higher delta is better for options buying
        delta_score = if delta >= 0.5
                        30 # Excellent delta
                      elsif delta >= 0.4
                        25  # Good delta
                      elsif delta >= 0.3
                        20  # Decent delta
                      else
                        10  # Poor delta
                      end

        # 4. IV Score (0-20)
        # Moderate IV is preferred (not too high, not too low)
        # ATM strikes get bonus for proximity even with lower IV
        # Use distance_from_atm to determine if it's ATM or ATM±1 (typically 50-100 points for NIFTY)
        is_atm_or_near = distance_from_atm <= (atm_strike * 0.005) # Within 0.5% of ATM (~125 points for NIFTY)

        iv_score = if iv.between?(15, 25)
                     20 # Sweet spot
                   elsif iv.between?(10, 30)
                     15  # Acceptable range
                   elsif iv.between?(5, 40)
                     10  # Marginal
                   else
                     5 # Poor IV
                   end
        # Bonus for ATM strikes with acceptable IV (even if lower)
        if is_atm_or_near && iv >= 5 && iv < 10
          iv_score += 5 # Boost score for ATM strikes with low but acceptable IV
        end

        # 5. Price Efficiency Score (0-10)
        # Lower price per point of delta is better
        price_efficiency = delta.positive? ? (ltp / delta) : ltp
        price_efficiency_score = if price_efficiency <= 200
                                   10 # Excellent efficiency
                                 elsif price_efficiency <= 300
                                   8   # Good efficiency
                                 elsif price_efficiency <= 500
                                   6   # Decent efficiency
                                 else
                                   4   # Poor efficiency
                                 end

        # Calculate total score
        atm_preference_score + liquidity_score + delta_score + iv_score + price_efficiency_score

        # Log scoring breakdown for debugging
        # Rails.logger.debug { "[Options] Strike #{strike_price} scoring:" }
        # Rails.logger.debug { "  - ATM Preference: #{atm_preference_score.round(1)} (distance: #{distance_from_atm.round(1)})" }
        # Rails.logger.debug { "  - Liquidity: #{liquidity_score.round(1)} (OI: #{oi}, Spread: #{spread_pct.round(2)}%)" }
        # Rails.logger.debug { "  - Delta: #{delta_score.round(1)} (delta: #{delta.round(3)})" }
        # Rails.logger.debug { "  - IV: #{iv_score.round(1)} (IV: #{iv.round(2)}%)" }
        # Rails.logger.debug { "  - Price Efficiency: #{price_efficiency_score.round(1)} (price/delta: #{price_efficiency.round(1)})" }
        # Rails.logger.debug { "  - Total Score: #{total_score.round(1)}" }
      end

      # Check if a strike is ITM (In-The-Money)
      def itm_strike?(strike_price, side, atm_strike)
        case side.to_sym
        when :ce, 'ce'
          # For calls: strike < ATM is ITM
          strike_price < atm_strike
        when :pe, 'pe'
          # For puts: strike > ATM is ITM
          strike_price > atm_strike
        else
          false
        end
      end

      # Log detailed filtering summary with explanations
      def log_filtering_summary(_side, accepted_count, rejected_count, _min_iv, _max_iv, _min_oi, _max_spread_pct,
                                _min_delta)
        total_processed = accepted_count + rejected_count
        total_processed.positive? ? (accepted_count.to_f / total_processed * 100).round(1) : 0

        # Rails.logger.info('[Options] Filtering Summary:')
        # Rails.logger.info("  - Total strikes processed: #{total_processed}")
        # Rails.logger.info("  - Accepted: #{accepted_count} (#{acceptance_rate}%)")
        # Rails.logger.info("  - Rejected: #{rejected_count} (#{100 - acceptance_rate}%)")
        # Rails.logger.info('  - Filter criteria applied:')
        # Rails.logger.info("    * IV Range: #{min_iv}-#{max_iv}%")
        # Rails.logger.info("    * Minimum OI: #{min_oi}")
        # Rails.logger.info("    * Maximum Spread: #{max_spread_pct}%")
        # Rails.logger.info("    * Minimum Delta: #{min_delta} (time-based)")

        if accepted_count.zero?
          # Rails.logger.warn('  - ⚠️  No strikes passed all filters - consider adjusting criteria')
        elsif accepted_count < 3
          # Rails.logger.info("  - ℹ️  Limited strikes available - #{accepted_count} option(s) found")
        else
          # Rails.logger.info("  - ✅ Good strike selection - #{accepted_count} options available")
        end
      end
    end
  end
end
