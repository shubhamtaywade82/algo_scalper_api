# frozen_string_literal: true

module Options
  # Enhanced ChainAnalyzer that uses Derivative records and integrates with existing infrastructure
  # This replaces the need for raw option chain APIs by leveraging existing Derivative models
  # rubocop:disable Metrics/ClassLength
  class DerivativeChainAnalyzer
    def initialize(index_key:, expiry: nil, config: {})
      @index_key = index_key.to_s.upcase
      @config = config || {}
      @expiry = expiry
      @index_cfg = AlgoConfig.fetch[:indices]&.find { |idx| idx[:key].to_s.upcase == @index_key }
      raise "unknown_index:#{@index_key}" unless @index_cfg
    end

    # Select best option candidates using Derivative records
    # @param limit [Integer] Maximum number of candidates to return
    # @param direction [Symbol] :bullish (CE) or :bearish (PE)
    # @return [Array<Hash>] Array of candidate hashes with derivative records
    def select_candidates(limit: 5, direction: :bullish)
      spot = spot_ltp
      return [] unless spot&.positive?

      expiry_date = @expiry || find_nearest_expiry
      return [] unless expiry_date

      chain = load_chain_for_expiry(expiry_date)
      return [] if chain.empty?

      atm = find_atm_strike(chain, spot)
      scored = score_chain(chain, atm, spot, direction)
      scored.sort_by { |c| -c[:score] }.first(limit)
    rescue StandardError => e
      Rails.logger.error("[Options::DerivativeChainAnalyzer] select_candidates failed: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      []
    end

    private

    # Get spot LTP from tick cache
    def spot_ltp
      seg = @index_cfg[:segment]
      sid = @index_cfg[:sid]
      Live::TickCache.ltp(seg, sid) || Live::RedisTickCache.instance.fetch_tick(seg, sid)&.dig(:ltp)&.to_f
    end

    # Find nearest expiry from Instrument's expiry list
    def find_nearest_expiry
      instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      return nil unless instrument

      expiry_list = instrument.expiry_list
      return nil unless expiry_list&.any?

      today = Time.zone.today
      parsed = expiry_list.compact.filter_map do |raw|
        case raw
        when Date then raw
        when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
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

    # Load chain using Derivative records and merge with live data
    def load_chain_for_expiry(expiry_date)
      expiry_obj = Date.parse(expiry_date)

      # Get all derivatives for this index and expiry
      derivatives = Derivative.where(
        underlying_symbol: @index_key,
        expiry_date: expiry_obj
      ).where.not(option_type: [nil, ''])

      return [] if derivatives.empty?

      # Fetch option chain data from API for OI/IV/Greeks
      api_chain = fetch_api_chain(expiry_date)
      return [] unless api_chain

      # Merge Derivative records with API data and live ticks
      derivatives.filter_map do |derivative|
        strike_str = derivative.strike_price.to_s
        option_type_lower = derivative.option_type.to_s.downcase
        api_data = api_chain.dig(strike_str, option_type_lower)

        # Get live tick data
        tick = Live::RedisTickCache.instance.fetch_tick(derivative.segment, derivative.security_id)

        build_option_data(derivative, api_data, tick)
      end
    end

    # Fetch option chain from DhanHQ API
    def fetch_api_chain(expiry_date)
      instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      return nil unless instrument

      chain_data = instrument.fetch_option_chain(expiry_date)
      return nil unless chain_data

      # Transform to strike -> { ce: {...}, pe: {...} } format
      oc = chain_data[:oc] || {}
      oc.transform_keys(&:to_s)
    rescue StandardError => e
      Rails.logger.warn("[Options::DerivativeChainAnalyzer] API chain fetch failed: #{e.message}")
      nil
    end

    # Build option data hash from Derivative, API data, and tick
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def build_option_data(derivative, api_data, tick)
      {
        derivative: derivative,
        strike: derivative.strike_price.to_f,
        type: derivative.option_type,
        expiry: derivative.expiry_date,
        segment: derivative.segment,
        security_id: derivative.security_id,
        lot_size: derivative.lot_size.to_i,
        ltp: tick&.dig(:ltp)&.to_f || api_data&.dig('last_price')&.to_f,
        oi: tick&.dig(:oi)&.to_i || api_data&.dig('oi')&.to_i,
        oi_change: tick&.dig(:oi_change)&.to_i,
        bid: tick&.dig(:bid)&.to_f || api_data&.dig('top_bid_price')&.to_f,
        ask: tick&.dig(:ask)&.to_f || api_data&.dig('top_ask_price')&.to_f,
        iv: api_data&.dig('implied_volatility')&.to_f,
        volume: tick&.dig(:volume)&.to_i || api_data&.dig('volume')&.to_i,
        prev_close: api_data&.dig('previous_close_price')&.to_f,
        delta: api_data&.dig('greeks', 'delta')&.to_f,
        gamma: api_data&.dig('greeks', 'gamma')&.to_f,
        theta: api_data&.dig('greeks', 'theta')&.to_f,
        vega: api_data&.dig('greeks', 'vega')&.to_f
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Find ATM strike from chain
    def find_atm_strike(chain, spot)
      return nil if chain.empty?

      chain.min_by { |o| (o[:strike] - spot).abs }[:strike]
    end

    # Score chain options based on multiple factors
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def score_chain(chain, atm, spot, direction)
      @direction = direction # Store for use in reason_for
      option_type = direction == :bullish ? 'CE' : 'PE'
      max_distance_pct = (@config[:strike_distance_pct] || 0.02).to_f
      max_distance = spot * max_distance_pct

      min_oi = (@config[:min_oi] || 10_000).to_i
      min_iv = (@config[:min_iv] || 5.0).to_f
      max_iv = (@config[:max_iv] || 60.0).to_f
      max_spread_pct = (@config[:max_spread_pct] || 0.03).to_f

      chain.select { |o| o[:type] == option_type }.filter_map do |option|
        # Filter criteria
        next if (option[:strike] - spot).abs > max_distance * 2
        next if option[:oi].to_i < min_oi
        next if option[:iv].to_f < min_iv || option[:iv].to_f > max_iv

        spread = calc_spread(option[:bid], option[:ask], option[:ltp])
        next if spread.nil? || spread > max_spread_pct

        # Calculate combined score
        score = combined_score(option, atm, spot, direction)

        {
          derivative: option[:derivative],
          strike: option[:strike],
          type: option[:type],
          score: score,
          ltp: option[:ltp],
          iv: option[:iv],
          oi: option[:oi],
          oi_change: option[:oi_change],
          spread: spread,
          delta: option[:delta],
          segment: option[:segment],
          security_id: option[:security_id],
          lot_size: option[:lot_size],
          symbol: build_symbol(option[:derivative], option[:strike], option[:type], option[:expiry]),
          derivative_id: option[:derivative]&.id,
          reason: reason_for(option, score, atm, spot)
        }
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Calculate bid-ask spread percentage
    def calc_spread(bid, ask, _ltp)
      return nil unless bid && ask && bid.positive?

      mid = (bid + ask) / 2.0
      return nil if mid <= 0

      (ask - bid) / mid
    end

    # Combined scoring function (heuristic - must be backtested)
    # rubocop:disable Metrics/AbcSize
    def combined_score(option, atm, spot, _direction)
      weights = @config[:scoring_weights] || {
        oi: 0.4,
        spread: 0.25,
        iv: 0.2,
        volume: 0.15
      }

      # Normalize OI (log scale, max ~1M = 6.0)
      oi_norm = Math.log10([option[:oi].to_i, 1].max) / 6.0
      oi_norm = [oi_norm, 1.0].min

      # Normalize spread (lower is better, inverted)
      spread = calc_spread(option[:bid], option[:ask], option[:ltp]) || 0.05
      spread_norm = 1.0 - [spread, 1.0].min

      # Normalize IV (prefer moderate IV around 20-25%)
      iv = option[:iv].to_f
      iv_norm = if iv.between?(15, 25)
                  1.0
                elsif iv.between?(10, 30)
                  0.8
                elsif iv.between?(5, 40)
                  0.6
                else
                  0.3
                end

      # Normalize volume (log scale)
      vol_norm = Math.log10([option[:volume].to_i, 1].max) / 6.0
      vol_norm = [vol_norm, 1.0].min

      # ATM preference bonus
      distance_from_atm = (option[:strike] - atm).abs
      atm_bonus = if distance_from_atm <= (spot * 0.005)
                    0.2 # Within 0.5% of ATM
                  elsif distance_from_atm <= (spot * 0.01)
                    0.1 # Within 1% of ATM
                  else
                    0.0
                  end

      base_score = (oi_norm * weights[:oi]) +
                   (spread_norm * weights[:spread]) +
                   (iv_norm * weights[:iv]) +
                   (vol_norm * weights[:volume])

      base_score + atm_bonus
    end
    # rubocop:enable Metrics/AbcSize

    # Build symbol string for candidate (compatible with BaseEngine)
    def build_symbol(derivative, strike, type, _expiry)
      return nil unless derivative

      expiry_str = derivative.expiry_date.strftime('%b%Y')
      "#{@index_key}-#{expiry_str}-#{strike.to_i}-#{type}"
    end

    # Generate human-readable reason for selection
    def reason_for(option, score, atm, spot)
      distance = (option[:strike] - spot).abs
      distance_pct = (distance / spot * 100).round(2)
      strike_type = if option[:strike] == atm
                      'ATM'
                    elsif option[:strike] > spot
                      direction == :bullish ? 'OTM' : 'ITM'
                    else
                      direction == :bullish ? 'ITM' : 'OTM'
                    end

      spread_pct = calc_spread(option[:bid], option[:ask], option[:ltp])
      spread_str = spread_pct ? "#{(spread_pct * 100).round(2)}%" : 'N/A'

      "Score:#{score.round(3)} IV:#{option[:iv]&.round(2)}% OI:#{option[:oi]} " \
        "Spread:#{spread_str} Strike:#{option[:strike]} (#{strike_type}, #{distance_pct}% from spot)"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
