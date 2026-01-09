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
      @index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @index_key }
      raise "unknown_index:#{@index_key}" unless @index_cfg
    end

    # Select best option candidates using Derivative records
    # @param limit [Integer] Maximum number of candidates to return
    # @param direction [Symbol] :bullish (CE) or :bearish (PE)
    # @return [Array<Hash>] Array of candidate hashes with derivative records
    def select_candidates(limit: 5, direction: :bullish)
      spot = spot_ltp
      unless spot&.positive?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No spot price for #{@index_key}")
        return []
      end

      expiry_date = @expiry || find_nearest_expiry
      unless expiry_date
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No expiry found for #{@index_key}")
        return []
      end

      chain = load_chain_for_expiry(expiry_date, spot)
      if chain.empty?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] Empty chain for #{@index_key} expiry #{expiry_date}")
        return []
      end

      atm = find_atm_strike(chain, spot)
      scored = score_chain(chain, atm, spot, direction)
      candidates = scored.sort_by { |c| -c[:score] }.first(limit)

      if candidates.empty?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No scored candidates for #{@index_key} (chain size: #{chain.size})")
      end

      candidates
    rescue StandardError => e
      Rails.logger.error("[Options::DerivativeChainAnalyzer] select_candidates failed for #{@index_key}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      []
    end

    # Get spot LTP from tick cache with API fallback
    # Public method for external access
    def spot_ltp
      seg = @index_cfg[:segment]
      sid = @index_cfg[:sid]

      # Try tick cache first
      spot = Live::TickCache.ltp(seg, sid)
      return spot if spot&.positive?

      # Try Redis cache
      spot = Live::RedisTickCache.instance.fetch_tick(seg, sid)&.dig(:ltp)&.to_f
      return spot if spot&.positive?

      # Fallback to API via Instrument.ltp()
      begin
        instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: sid.to_s)
        if instrument
          spot = instrument.ltp&.to_f
          return spot if spot&.positive?
        end
      rescue StandardError => e
        Rails.logger.debug { "[Options::DerivativeChainAnalyzer] API fallback failed for spot: #{e.message}" }
      end

      nil
    end

    # Find nearest expiry from Instrument's expiry list
    # Public method for external access
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

    # Public alias for find_nearest_expiry
    alias nearest_expiry find_nearest_expiry

    # Load chain using Derivative records and merge with live data
    # Public method for external access
    def load_chain_for_expiry(expiry_date, spot)
      # Convert expiry_date to Date object if it's a string
      expiry_obj = expiry_date.is_a?(Date) ? expiry_date : Date.parse(expiry_date.to_s)

      # Get all derivatives for this index and expiry
      # Exclude TEST_ security IDs completely - never use test derivatives
      derivatives_relation = Derivative.where(
        underlying_symbol: @index_key,
        expiry_date: expiry_obj
      ).where.not(option_type: [nil, ''])
                                       .where.not("security_id LIKE 'TEST_%'")
      derivatives = derivatives_relation

      if derivatives.empty?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No derivatives in DB for #{@index_key} expiry #{expiry_obj}")
        return []
      end

      Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Found #{derivatives.count} derivatives for #{@index_key} expiry #{expiry_obj}" }

      # Fetch option chain data from API for OI/IV/Greeks
      # Convert expiry_date to string format for API call (YYYY-MM-DD)
      expiry_str = expiry_obj.is_a?(Date) ? expiry_obj.strftime('%Y-%m-%d') : expiry_date.to_s
      api_chain = fetch_api_chain(expiry_str)

      # If API chain is available, filter derivatives to only include strikes that exist in API chain
      if api_chain && api_chain.any?
        # Get all strikes from API chain (keys are strike strings like "22700.000000")
        api_strikes = api_chain.keys.map { |k| BigDecimal(k.to_s) }.to_set

        # Filter derivatives to only those with strikes in API chain
        original_count = derivatives.count
        derivatives = if derivatives.respond_to?(:where)
                        derivatives.where(strike_price: api_strikes.to_a)
                      else
                        filtered_ids = Array(derivatives).select do |d|
                          strike_bd = BigDecimal(d.strike_price.to_s)
                          api_strikes.include?(strike_bd)
                        end.map(&:id)
                        Derivative.where(id: filtered_ids)
                      end

        if derivatives.count < original_count
          Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Filtered derivatives: #{original_count} -> #{derivatives.count} (only strikes in API chain)" }
        end
      end

      unless api_chain
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] API chain fetch failed for #{@index_key} expiry #{expiry_str}, but continuing with DB-only data")
        # Continue with DB derivatives only - API data is optional for basic functionality
        # This allows the system to work even if API is unavailable
      end

      # Calculate approximate ATM strike for limiting queries/LTP fetches
      strike_increment = strike_increment_for(spot)
      atm_strike_approx = nil
      if spot&.positive? && strike_increment.positive?
        atm_strike_approx = (spot / strike_increment).round * strike_increment
        Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Spot: ₹#{spot}, ATM strike approx: #{atm_strike_approx}, increment: #{strike_increment}" }
      else
        Rails.logger.warn('[Options::DerivativeChainAnalyzer] No spot price available for ATM calculation')
      end

      # Limit derivatives to a small strike window around ATM to avoid scanning entire chain
      # Only consider ATM, 1OTM, and 2OTM (window = 2, max)
      if atm_strike_approx
        window = (@config[:strike_window_steps] || 2).to_i
        window = 2 if window <= 0 || window > 2 # Cap at 2OTM only
        target_strikes = (-window..window).map do |offset|
          atm_strike_approx + (offset * strike_increment)
        end.select { |strike| strike.positive? }.uniq

        if target_strikes.any?
          target_strikes_bd = target_strikes.map { |strike| BigDecimal(strike.to_s) }
          filtered = if derivatives.respond_to?(:where)
                       derivatives.where(strike_price: target_strikes_bd)
                     else
                       filtered_ids = Array(derivatives).select do |d|
                         strike_bd = BigDecimal(d.strike_price.to_s)
                         target_strikes_bd.include?(strike_bd)
                       end.map(&:id)
                       Derivative.where(id: filtered_ids)
                     end

          filtered_count = filtered.count
          if filtered_count.positive?
            Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Limiting strikes to ATM±#{window} (#{target_strikes.size} targets)" }
            derivatives = filtered
          else
            Rails.logger.debug('[Options::DerivativeChainAnalyzer] Strike filtering found no records, using full derivative set')
          end
        end
      end

      # BATCH LTP FETCH: Collect all derivatives that need LTP and fetch in ONE API call
      # This replaces the previous approach of calling API individually for each strike
      batch_ltp_results = batch_fetch_ltp_for_derivatives(derivatives, atm_strike_approx)

      # Merge Derivative records with API data and live ticks
      # If api_chain is nil, we'll still build candidates using just DB and tick data
      built_count = 0
      result = derivatives.filter_map do |derivative|
        # Skip any TEST_ derivatives that might have slipped through (shouldn't happen due to query filter)
        next if derivative.security_id.to_s.start_with?('TEST_')

        # Try multiple strike formats to match API chain keys (e.g., "27950.000000", "27950.0", "27950")
        strike_float = derivative.strike_price.to_f
        strike_formats = [
          format('%.6f', strike_float), # "27950.000000" - API format
          strike_float.to_s,              # "27950.0" - default float format
          strike_float.to_i.to_s,         # "27950" - integer format
          format('%.2f', strike_float) # "27950.00" - 2 decimal places
        ].uniq

        option_type_lower = derivative.option_type.to_s.downcase
        api_data = nil

        # Try each format until we find a match
        strike_formats.each do |strike_str|
          api_data = api_chain&.dig(strike_str, option_type_lower)
          break if api_data
        end

        # Get live tick data - use exchange_segment (NSE_FNO) not segment (derivatives)
        exchange_seg = derivative.exchange_segment || 'NSE_FNO'
        tick = Live::RedisTickCache.instance.fetch_tick(exchange_seg, derivative.security_id)

        # If no tick data, check batch LTP results
        if !tick || !tick[:ltp]&.positive?
          batch_ltp = batch_ltp_results[derivative.security_id.to_s]
          if batch_ltp&.positive?
            tick = tick ? tick.dup : {}
            tick[:ltp] = batch_ltp
          end
        end

        data = build_option_data(derivative, api_data, tick)
        built_count += 1 if data
        data
      end

      Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Built #{result.size} option data entries from #{derivatives.count} derivatives" }
      result
    end

    # Batch fetch LTP for multiple derivatives in ONE API call
    # This is much more efficient than calling API for each strike individually
    # @param derivatives [ActiveRecord::Relation] Derivatives to fetch LTP for
    # @param atm_strike_approx [Float] Approximate ATM strike for filtering
    # @return [Hash] { security_id => ltp } mapping
    def batch_fetch_ltp_for_derivatives(derivatives, atm_strike_approx)
      return {} unless derivatives.any?

      # Collect all security IDs that need LTP (within 2 strikes of ATM)
      strike_increment = atm_strike_approx.to_f >= 10_000 ? 100 : 50
      max_distance = strike_increment * 2

      security_ids_by_segment = Hash.new { |h, k| h[k] = [] }

      derivatives.each do |derivative|
        next if derivative.security_id.to_s.start_with?('TEST_')

        # Check if already in tick cache
        exchange_seg = derivative.exchange_segment || 'NSE_FNO'
        tick = Live::RedisTickCache.instance.fetch_tick(exchange_seg, derivative.security_id)
        next if tick && tick[:ltp]&.positive?

        # Only fetch for ATM candidates (within 2 strikes)
        if atm_strike_approx
          strike_distance = (derivative.strike_price.to_f - atm_strike_approx).abs
          next if strike_distance > max_distance
        end

        segment = derivative.exchange_segment || 'NSE_FNO'
        security_ids_by_segment[segment] << derivative.security_id.to_i
      end

      return {} if security_ids_by_segment.empty?

      # Make ONE batch API call per segment (typically just NSE_FNO)
      results = {}
      security_ids_by_segment.each do |segment, security_ids|
        next if security_ids.empty?

        Rails.logger.info("[Options::DerivativeChainAnalyzer] Batch fetching LTP for #{security_ids.size} derivatives (segment: #{segment})")

        begin
          payload = { segment => security_ids }
          response = DhanHQ::Models::MarketFeed.ltp(payload)

          if response.is_a?(Hash) && response['status'] == 'success'
            data = response.dig('data', segment) || {}
            data.each do |sid, quote|
              ltp = quote&.dig('last_price')
              if ltp&.positive?
                results[sid.to_s] = ltp
                Rails.logger.debug { "[Options::DerivativeChainAnalyzer] ✅ Batch LTP for #{sid}: ₹#{ltp}" }
              end
            end
            Rails.logger.info("[Options::DerivativeChainAnalyzer] ✅ Batch fetched #{results.size} LTPs in ONE API call")
          else
            Rails.logger.warn("[Options::DerivativeChainAnalyzer] Batch LTP response not success: #{response}")
          end
        rescue StandardError => e
          error_msg = e.message.to_s
          is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit')
          unless is_rate_limit
            Rails.logger.error("[Options::DerivativeChainAnalyzer] Batch LTP fetch failed: #{e.class} - #{e.message}")
          end
        end
      end

      results
    end

    # Fetch option chain from DhanHQ API
    def fetch_api_chain(expiry_date)
      instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      unless instrument
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No instrument found for #{@index_key}")
        return nil
      end

      chain_data = instrument.fetch_option_chain(expiry_date)
      unless chain_data
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] fetch_option_chain returned nil for #{@index_key} expiry #{expiry_date}")
        return nil
      end

      # Transform to strike -> { ce: {...}, pe: {...} } format
      oc = chain_data[:oc] || {}
      if oc.empty?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] Option chain data empty for #{@index_key} expiry #{expiry_date}")
        return nil
      end

      oc.transform_keys(&:to_s)
    rescue StandardError => e
      Rails.logger.error("[Options::DerivativeChainAnalyzer] API chain fetch failed for #{@index_key} expiry #{expiry_date}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
      nil
    end

    # Build option data hash from Derivative, API data, and tick
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def build_option_data(derivative, api_data, tick)
      # Use exchange_segment (NSE_FNO) not segment (derivatives) for API calls
      exchange_seg = derivative.exchange_segment || 'NSE_FNO'

      # Calculate OI change: prefer tick data, fallback to API data (current_oi - previous_oi)
      current_oi = tick&.dig(:oi)&.to_i || api_data&.dig('oi')&.to_i || 0
      oi_change_from_tick = tick&.dig(:oi_change)&.to_i
      previous_oi = api_data&.dig('previous_oi')&.to_i || 0
      oi_change = if oi_change_from_tick && oi_change_from_tick != 0
                    oi_change_from_tick
                  elsif current_oi.positive? && previous_oi.positive?
                    current_oi - previous_oi
                  else
                    0
                  end

      {
        derivative: derivative,
        strike: derivative.strike_price.to_f,
        type: derivative.option_type,
        expiry: derivative.expiry_date,
        segment: exchange_seg, # Use exchange_segment for consistency
        security_id: derivative.security_id,
        lot_size: derivative.lot_size.to_i,
        ltp: tick&.dig(:ltp)&.to_f || api_data&.dig('last_price')&.to_f,
        oi: current_oi,
        oi_change: oi_change,
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
      return nil unless spot&.positive?

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

      # Check if we have API data (OI/IV available) - if not, relax filters
      has_api_data = chain.any? { |o| o[:oi].to_i.positive? || o[:iv].to_f.positive? }

      unless has_api_data
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No API data available - relaxing filters for #{@index_key}")
        min_oi = 0 # Allow any OI if API data unavailable
        min_iv = 0 # Allow any IV if API data unavailable
        max_iv = 999.0 # Allow any IV if API data unavailable
      end

      candidates_with_ltp = 0
      candidates_filtered = 0
      result = chain.select { |o| o[:type] == option_type }.filter_map do |option|
        # Filter criteria
        strike_distance = (option[:strike] - spot).abs
        if strike_distance > max_distance * 2
          candidates_filtered += 1
          next
        end

        # Require LTP for scoring (can't score without price)
        # LTP should already be populated from batch fetch in load_chain_for_expiry
        # Skip candidates without LTP - batch fetch already tried to get it
        unless option[:ltp]&.positive?
          candidates_filtered += 1
          next
        end

        candidates_with_ltp += 1

        # Only filter by OI/IV if we have API data
        if has_api_data
          next if option[:oi].to_i < min_oi
          next if option[:iv].to_f < min_iv || option[:iv].to_f > max_iv
        end

        spread = calc_spread(option[:bid], option[:ask], option[:ltp])
        # Only filter by spread if we have bid/ask data
        next if spread && has_api_data && (spread > max_spread_pct)

        # Calculate combined score
        score = combined_score(option, atm, spot, direction)

        # Skip if score is 0 or negative (invalid candidate)
        next unless score&.positive?

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
          reason: reason_for(option, score, atm, spot, direction)
        }
      end

      Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Scoring: #{candidates_with_ltp} with LTP, #{candidates_filtered} filtered, #{result.size} scored for #{@index_key}" }
      result
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Calculate bid-ask spread percentage
    def calc_spread(bid, ask, _ltp)
      return nil unless bid && ask && bid.positive?

      mid = (bid + ask) / 2.0
      return nil if mid <= 0

      (ask - bid) / mid
    end

    def strike_increment_for(spot)
      return 0 unless spot&.positive?

      if spot >= 50_000
        100
      elsif spot >= 10_000
        50
      else
        25
      end
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
    def reason_for(option, score, atm, spot, direction)
      trade_direction = direction.to_s.downcase.to_sym
      distance = (option[:strike] - spot).abs
      distance_pct = (distance / spot * 100).round(2)
      strike_type = if option[:strike] == atm
                      'ATM'
                    elsif option[:strike] > spot
                      trade_direction == :bullish ? 'OTM' : 'ITM'
                    else
                      trade_direction == :bullish ? 'ITM' : 'OTM'
                    end

      spread_pct = calc_spread(option[:bid], option[:ask], option[:ltp])
      spread_str = spread_pct ? "#{(spread_pct * 100).round(2)}%" : 'N/A'

      "Score:#{score.round(3)} IV:#{option[:iv]&.round(2)}% OI:#{option[:oi]} " \
        "Spread:#{spread_str} Strike:#{option[:strike]} (#{strike_type}, #{distance_pct}% from spot)"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
