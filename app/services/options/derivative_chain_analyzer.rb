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
      unless spot&.positive?
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No spot price for #{@index_key}")
        return []
      end

      expiry_date = @expiry || find_nearest_expiry
      unless expiry_date
        Rails.logger.warn("[Options::DerivativeChainAnalyzer] No expiry found for #{@index_key}")
        return []
      end

      chain = load_chain_for_expiry(expiry_date)
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

    private

    # Get spot LTP from tick cache with API fallback
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
      # Convert expiry_date to Date object if it's a string
      expiry_obj = expiry_date.is_a?(Date) ? expiry_date : Date.parse(expiry_date.to_s)

      # Get all derivatives for this index and expiry
      # Exclude TEST_ security IDs completely - never use test derivatives
      derivatives = Derivative.where(
        underlying_symbol: @index_key,
        expiry_date: expiry_obj
      ).where.not(option_type: [nil, ''])
                              .where.not("security_id LIKE 'TEST_%'")

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
        derivatives = derivatives.select do |d|
          strike_bd = BigDecimal(d.strike_price.to_s)
          api_strikes.include?(strike_bd)
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

      # Calculate approximate ATM strike for limiting LTP fetches (performance optimization)
      spot = spot_ltp
      atm_strike_approx = nil
      if spot&.positive?
        # Estimate ATM strike (round to nearest 50 for NIFTY, 100 for BANKNIFTY)
        strike_increment = spot >= 50_000 ? 100 : 50
        atm_strike_approx = (spot / strike_increment).round * strike_increment
        Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Spot: ₹#{spot}, ATM strike approx: #{atm_strike_approx}, increment: #{strike_increment}" }
      else
        Rails.logger.warn('[Options::DerivativeChainAnalyzer] No spot price available for ATM calculation')
      end

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

        # For ATM candidates (within 2 strikes), try API fallback if no tick data
        # This is a performance optimization - we can't fetch LTP for 500+ derivatives
        if (!tick || !tick[:ltp]&.positive?) && atm_strike_approx
          strike_distance = (derivative.strike_price.to_f - atm_strike_approx).abs
          strike_increment = derivative.strike_price.to_f >= 10_000 ? 100 : 50
          max_distance = strike_increment * 2

          if strike_distance <= max_distance # Within 2 strikes of ATM
            # Try API fallback using fetch_ltp_from_api_for_segment (includes WebSocket subscription logic)
            begin
              # Derivatives use NSE_FNO segment, not 'derivatives'
              segment = derivative.exchange_segment || 'NSE_FNO'
              security_id = derivative.security_id.to_s

              # Skip if segment or security_id is missing (shouldn't happen for real derivatives)
              if segment.present? && security_id.present?
                Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Fetching LTP for ATM candidate: #{derivative.symbol_name} (strike: #{derivative.strike_price}, distance: #{strike_distance.round(0)}, segment: #{segment}, sid: #{security_id})" }

                # Use InstrumentHelpers method directly (includes WebSocket subscription + API fallback)
                api_ltp = derivative.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
                if api_ltp&.positive?
                  tick = tick ? tick.dup : {}
                  tick[:ltp] = api_ltp
                  Rails.logger.info("[Options::DerivativeChainAnalyzer] ✅ Got LTP from API for #{derivative.symbol_name}: ₹#{api_ltp}")
                else
                  Rails.logger.debug { "[Options::DerivativeChainAnalyzer] ⚠️  API LTP fetch returned nil for #{derivative.symbol_name}" }
                end
              else
                Rails.logger.debug { "[Options::DerivativeChainAnalyzer] ⚠️  Missing segment or security_id for #{derivative.symbol_name}: segment=#{segment}, sid=#{security_id}" }
              end
            rescue StandardError => e
              Rails.logger.warn("[Options::DerivativeChainAnalyzer] ❌ API LTP fetch failed for #{derivative.symbol_name}: #{e.class} - #{e.message}")
            end
          end
        end

        data = build_option_data(derivative, api_data, tick)
        built_count += 1 if data
        data
      end

      Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Built #{result.size} option data entries from #{derivatives.count} derivatives" }
      result
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

      {
        derivative: derivative,
        strike: derivative.strike_price.to_f,
        type: derivative.option_type,
        expiry: derivative.expiry_date,
        segment: exchange_seg, # Use exchange_segment for consistency
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
        # For ATM candidates, try one more time to get LTP if missing
        unless option[:ltp]&.positive?
          # Last chance: try API for ATM strikes only
          strike_distance_check = (option[:strike] - spot).abs
          max_distance_check = spot * 0.02 * 2 # Same as filter above
          if strike_distance_check <= max_distance_check && option[:derivative]
            begin
              derivative = option[:derivative]
              segment = derivative.exchange_segment || 'NSE_FNO'
              security_id = derivative.security_id.to_s

              # Skip if segment or security_id is missing (shouldn't happen for real derivatives)
              if segment.present? && security_id.present?
                api_ltp = derivative.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
                if api_ltp&.positive?
                  option[:ltp] = api_ltp
                  Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Got LTP in score_chain for #{derivative.symbol_name}: ₹#{api_ltp}" }
                end
              end
            rescue StandardError => e
              Rails.logger.debug { "[Options::DerivativeChainAnalyzer] Final LTP fetch failed: #{e.message}" }
            end
          end

          # Still no LTP? Skip this candidate
          unless option[:ltp]&.positive?
            candidates_filtered += 1
            next
          end
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
          reason: reason_for(option, score, atm, spot)
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
