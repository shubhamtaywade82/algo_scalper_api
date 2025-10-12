# frozen_string_literal: true

module Options
  class ChainAnalyzer
    class << self
      def pick_strikes(index_cfg:, direction:)
        Rails.logger.info("[Options] Starting strike selection for #{index_cfg[:key]} #{direction}")

        # Get cached index instrument
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.warn("[Options] No instrument found for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.debug("[Options] Using instrument: #{instrument.symbol_name}")

        # Use instrument's existing methods to get expiry list and option chain
        expiry_list = instrument.expiry_list
        unless expiry_list&.any?
          Rails.logger.warn("[Options] No expiry list available for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.debug("[Options] Available expiries: #{expiry_list}")

        # Get the next upcoming expiry
        expiry_date = find_next_expiry(expiry_list)
        unless expiry_date
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.info("[Options] Using expiry: #{expiry_date}")

        # Fetch option chain using instrument's method
        chain_data = instrument.fetch_option_chain(expiry_date)
        unless chain_data
          Rails.logger.warn("[Options] No option chain data for #{index_cfg[:key]} #{expiry_date}")
          return []
        end

        Rails.logger.debug("[Options] Chain data structure: #{chain_data.keys}")
        Rails.logger.debug("[Options] OC data size: #{chain_data[:oc]&.size || 'nil'}")

        # Debug: Show sample of raw option data
        if chain_data[:oc] && chain_data[:oc].any?
          sample_strike = chain_data[:oc].keys.first
          sample_data = chain_data[:oc][sample_strike]
          Rails.logger.debug("[Options] Sample strike #{sample_strike} data: #{sample_data}")
          if sample_data["pe"]
            Rails.logger.debug("[Options] Sample PE data: #{sample_data["pe"]}")
          end
        end

        atm_price = chain_data[:last_price]
        unless atm_price
          Rails.logger.warn("[Options] No ATM price available for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.info("[Options] ATM price: #{atm_price}")

        side = direction == :bullish ? :ce : :pe
        # For buying options, focus on ATM and ATM+1 strikes only
        # This prevents selecting expensive ITM options
        Rails.logger.debug("[Options] Looking for #{side} options at ATM and ATM#{side == :ce || side == "ce" ? "+1" : "-1"} strikes only")

        legs = filter_and_rank_from_instrument_data(chain_data[:oc], atm: atm_price, side: side, index_cfg: index_cfg, expiry_date: expiry_date, instrument: instrument)
        Rails.logger.info("[Options] Found #{legs.size} qualifying #{side} options for #{index_cfg[:key]}")

        if legs.any?
          Rails.logger.info("[Options] Top picks: #{legs.first(2).map { |l| "#{l[:symbol]}@#{l[:strike]} (Score:#{l[:score]&.round(1)}, IV:#{l[:iv]}, OI:#{l[:oi]})" }.join(', ')}")
        end

        legs.first(2).map do |leg|
          leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread, :lot_size)
        end
      end

      def find_next_expiry(expiry_list)
        return nil unless expiry_list&.any?

        today = Date.current
        upcoming_expiries = expiry_list
          .map { |date_str| Date.parse(date_str.to_s) rescue nil }
          .compact
          .select { |date| date > today }
          .sort

        upcoming_expiries.first&.strftime("%Y-%m-%d")
      rescue StandardError => e
        Rails.logger.warn("Failed to parse expiry list: #{e.class} - #{e.message}")
        calculate_next_trading_day
      end

      def calculate_next_trading_day
        # Use Market::Calendar to find the next trading day dynamically
        # This replaces the hardcoded Thursday logic
        Market::Calendar.next_trading_day.strftime("%Y-%m-%d")
      end

      def filter_and_rank_from_instrument_data(option_chain_data, atm:, side:, index_cfg:, expiry_date:, instrument:)
        # Force reload - debugging index_cfg scope issue
        return [] unless option_chain_data

        Rails.logger.debug("[Options] Method called with index_cfg: #{index_cfg[:key]}, expiry_date: #{expiry_date}")

        Rails.logger.debug("[Options] Processing #{option_chain_data.size} strikes for #{side} options")

        # Calculate strike interval dynamically from available strikes
        strikes = option_chain_data.keys.map(&:to_f).sort
        oc_strikes = strikes  # Make strikes available for ATM range calculation

        strike_interval = if strikes.size >= 2
                           strikes[1] - strikes[0]
        else
                           50 # fallback
        end

        atm_strike = (atm / strike_interval).round * strike_interval

        # Calculate dynamic ATM range based on volatility
        # For now, we'll use a default IV rank of 0.5 (medium volatility)
        # TODO: Integrate with actual IV rank calculation
        iv_rank = 0.5  # Default to medium volatility
        atm_range_percent = atm_range_pct(iv_rank)
        atm_range_points = atm * atm_range_percent

        Rails.logger.debug("[Options] SPOT: #{atm}, Strike interval: #{strike_interval}, ATM strike: #{atm_strike}")
        Rails.logger.debug("[Options] IV Rank: #{iv_rank}, ATM range: #{atm_range_percent * 100}% (#{atm_range_points.round(2)} points)")

        # For bullish: ATM and strikes within ATM range above current price
        # For bearish: ATM and strikes within ATM range below current price
        target_strikes = if side == :ce || side == "ce"
                          # CE: ATM and strikes up to ATM + range
                          strikes_in_range = oc_strikes.select do |s|
                            s >= atm_strike && s <= (atm_strike + atm_range_points)
                          end
                          strikes_in_range.first(3) # Limit to top 3 strikes
        else
                          # PE: ATM and strikes down to ATM - range
                          strikes_in_range = oc_strikes.select do |s|
                            s <= atm_strike && s >= (atm_strike - atm_range_points)
                          end
                          strikes_in_range.first(3) # Limit to top 3 strikes
        end

        Rails.logger.debug("[Options] Target strikes for #{side}: #{target_strikes}")

        # Log strike selection guidance
        log_strike_selection_guidance(side, atm, atm_strike, target_strikes, iv_rank, atm_range_percent)

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        min_delta = min_delta_now
        Rails.logger.debug("[Options] Filter criteria: IV(#{min_iv}-#{max_iv}), OI(>=#{min_oi}), Spread(<=#{max_spread_pct}%), Delta(>=#{min_delta})")

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
          if rejected_count < 3
            Rails.logger.debug("[Options] Available fields for #{side}: #{option_data.keys}")
          end

          ltp = option_data["last_price"]&.to_f
          iv = option_data["implied_volatility"]&.to_f
          oi = option_data["oi"]&.to_i
          bid = option_data["top_bid_price"]&.to_f
          ask = option_data["top_ask_price"]&.to_f

          strike_type = if strike == atm_strike
                          "ATM"
          elsif side == :ce || side == "ce"
                          strike == atm_strike + strike_interval ? "ATM+1" : "OTHER"
          else
                          strike == atm_strike - strike_interval ? "ATM-1" : "OTHER"
          end
          Rails.logger.debug("[Options] Strike #{strike} (#{strike_type}): LTP=#{ltp}, IV=#{iv}, OI=#{oi}, Bid=#{bid}, Ask=#{ask}")

          # Check LTP
          unless ltp && ltp > 0
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: Invalid LTP")
            next
          end

          # Check IV
          unless iv && iv >= min_iv && iv <= max_iv
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: IV #{iv} not in range #{min_iv}-#{max_iv}")
            next
          end

          # Check OI
          unless oi && oi >= min_oi
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: OI #{oi} < #{min_oi}")
            next
          end

          # Calculate spread percentage
          if bid && ask && bid > 0
            spread_pct = ((ask - bid) / bid) * 100
            if spread_pct > max_spread_pct
              rejected_count += 1
              Rails.logger.debug("[Options] Rejected #{strike}: Spread #{spread_pct}% > #{max_spread_pct}%")
              next
            end
          end

          # Check Delta (time-based thresholds)
          delta = option_data.dig("greeks", "delta")&.to_f&.abs
          unless delta && delta >= min_delta
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: Delta #{delta} < #{min_delta}")
            next
          end

          # Find the derivative security ID using instrument.derivatives association
          # Filter by strike, expiry date, and option type
          expiry_date_obj = Date.parse(expiry_date)
          option_type = side.to_s.upcase # CE or PE

          derivative = instrument.derivatives.find do |d|
            d.strike_price == strike.to_f &&
            d.expiry_date == expiry_date_obj &&
            d.option_type == option_type
          end

          if derivative
            Rails.logger.debug("[Options] Found derivative for #{index_cfg[:key]} #{strike} #{side}: security_id=#{derivative.security_id}, lot_size=#{derivative.lot_size}")
            security_id = derivative.security_id
          else
            Rails.logger.warn("[Options] No derivative found for #{index_cfg[:key]} #{strike} #{side} #{expiry_date}")
            security_id = nil
          end

          legs << {
            segment: "NSE_FNO", # Default segment for index options
            security_id: security_id,
            symbol: "#{index_cfg[:key]}-#{expiry_date_obj.strftime('%b%Y')}-#{strike.to_i}-#{side.to_s.upcase}",
            strike: strike,
            ltp: ltp,
            iv: iv,
            oi: oi,
            spread: ask && bid ? (ask - bid) : nil,
            distance_from_atm: (strike - atm).abs,
            lot_size: derivative&.lot_size || index_cfg[:lot].to_i
          }

          Rails.logger.debug("[Options] Accepted #{strike}: #{legs.last[:symbol]}")
        end

        Rails.logger.info("[Options] Filter results: #{legs.size} accepted, #{rejected_count} rejected")

        # Log detailed filtering summary
        log_filtering_summary(side, legs.size, rejected_count, min_iv, max_iv, min_oi, max_spread_pct, min_delta)

        # Apply sophisticated scoring system
        scored_legs = legs.map do |leg|
          score = calculate_strike_score(leg, side, atm_strike, atm_range_percent)
          leg.merge(score: score)
        end

        # Sort by score (descending), then by distance from ATM
        scored_legs.sort_by { |leg| [ -leg[:score], leg[:distance_from_atm] ] }
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
        end.sort_by { |leg| [ -leg[:oi].to_i, leg.fetch(:spread_pct, 0.0).to_f ] }
      end

      # Dynamic minimum delta thresholds depending on time of day
      # Higher delta requirements as market approaches close to avoid theta decay
      def min_delta_now
        h = Time.zone.now.hour
        return 0.45 if h >= 14  # After 2 PM - high delta to avoid theta decay
        return 0.35 if h >= 13  # After 1 PM - medium-high delta
        return 0.30 if h >= 11  # After 11 AM - medium delta
        0.25                    # Before 11 AM - lower delta acceptable
      end

      # Dynamic ATM range based on volatility (IV rank)
      # Low volatility = tight range, High volatility = wider range
      def atm_range_pct(iv_rank = 0.5)
        case iv_rank
        when 0.0..0.2 then 0.01   # Low volatility - tight range (1%)
        when 0.2..0.5 then 0.015 # Medium volatility - medium range (1.5%)
        else 0.025               # High volatility - wider range (2.5%)
        end
      end

      # Log comprehensive strike selection guidance
      def log_strike_selection_guidance(side, spot, atm_strike, target_strikes, iv_rank, atm_range_percent)
        volatility_regime = case iv_rank
        when 0.0..0.2 then "Low"
        when 0.2..0.5 then "Medium"
        else "High"
        end

        explanation = if side == :ce || side == "ce"
                       "CE strikes should be ATM or slightly OTM (never ITM) - buying calls above current price"
        else
                       "PE strikes should be ATM or slightly OTM (never ITM) - buying puts below current price"
        end

        Rails.logger.info("[Options] Strike Selection Guidance:")
        Rails.logger.info("  - Current SPOT: #{spot}")
        Rails.logger.info("  - ATM Strike: #{atm_strike}")
        Rails.logger.info("  - Volatility Regime: #{volatility_regime} (IV Rank: #{iv_rank})")
        Rails.logger.info("  - ATM Range: #{atm_range_percent * 100}%")
        Rails.logger.info("  - Target Strikes: #{target_strikes}")
        Rails.logger.info("  - Strategy: #{explanation}")

        # Log strike analysis
        target_strikes.each_with_index do |strike, index|
          distance_from_atm = (strike - atm_strike).abs
          distance_from_spot = (strike - spot).abs
          strike_type = if strike == atm_strike
                          "ATM"
          elsif side == :ce || side == "ce"
                          strike > atm_strike ? "OTM" : "ITM"
          else
                          strike < atm_strike ? "OTM" : "ITM"
          end

          Rails.logger.info("  - Strike #{index + 1}: #{strike} (#{strike_type}) - #{distance_from_atm} points from ATM, #{distance_from_spot.round(2)} points from spot")
        end
      end

      # Calculate sophisticated strike score based on multiple factors
      def calculate_strike_score(leg, side, atm_strike, atm_range_percent)
        strike_price = leg[:strike_price]
        ltp = leg[:ltp]
        iv = leg[:iv]
        oi = leg[:oi]
        spread_pct = leg[:spread_pct]
        delta = leg[:delta] || 0.5 # Default delta if not available
        
        # 1. ATM Preference Score (0-100)
        distance_from_atm = (strike_price - atm_strike).abs
        atm_range_points = atm_strike * atm_range_percent
        
        atm_preference_score = if distance_from_atm <= (atm_range_points * 0.1)
                                 100  # Perfect ATM
                                elsif distance_from_atm <= (atm_range_points * 0.3)
                                  80  # Near ATM
                                elsif distance_from_atm <= (atm_range_points * 0.6)
                                  50  # Slightly away
                                else
                                  20  # Far from ATM
                                end
        
        # Penalty for ITM strikes (30% reduction)
        if itm_strike?(strike_price, side, atm_strike)
          atm_preference_score *= 0.7
        end
        
        # 2. Liquidity Score (0-50)
        # Based on OI and spread
        liquidity_score = if oi >= 1000000
                            50  # Excellent liquidity
                           elsif oi >= 500000
                            40  # Good liquidity
                           elsif oi >= 100000
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
                        30  # Excellent delta
                       elsif delta >= 0.4
                        25  # Good delta
                       elsif delta >= 0.3
                        20  # Decent delta
                       else
                        10  # Poor delta
                       end
        
        # 4. IV Score (0-20)
        # Moderate IV is preferred (not too high, not too low)
        iv_score = if iv >= 15 && iv <= 25
                     20  # Sweet spot
                    elsif iv >= 10 && iv <= 30
                     15  # Acceptable range
                    elsif iv >= 5 && iv <= 40
                     10  # Marginal
                    else
                      5  # Poor IV
                    end
        
        # 5. Price Efficiency Score (0-10)
        # Lower price per point of delta is better
        price_efficiency = delta > 0 ? (ltp / delta) : ltp
        price_efficiency_score = if price_efficiency <= 200
                                   10  # Excellent efficiency
                                  elsif price_efficiency <= 300
                                    8   # Good efficiency
                                  elsif price_efficiency <= 500
                                    6   # Decent efficiency
                                  else
                                    4   # Poor efficiency
                                  end
        
        # Calculate total score
        total_score = atm_preference_score + liquidity_score + delta_score + iv_score + price_efficiency_score
        
        # Log scoring breakdown for debugging
        Rails.logger.debug("[Options] Strike #{strike_price} scoring:")
        Rails.logger.debug("  - ATM Preference: #{atm_preference_score.round(1)} (distance: #{distance_from_atm.round(1)})")
        Rails.logger.debug("  - Liquidity: #{liquidity_score.round(1)} (OI: #{oi}, Spread: #{spread_pct.round(2)}%)")
        Rails.logger.debug("  - Delta: #{delta_score.round(1)} (delta: #{delta.round(3)})")
        Rails.logger.debug("  - IV: #{iv_score.round(1)} (IV: #{iv.round(2)}%)")
        Rails.logger.debug("  - Price Efficiency: #{price_efficiency_score.round(1)} (price/delta: #{price_efficiency.round(1)})")
        Rails.logger.debug("  - Total Score: #{total_score.round(1)}")
        
        total_score
      end
      
      # Check if a strike is ITM (In-The-Money)
      def itm_strike?(strike_price, side, atm_strike)
        case side.to_sym
        when :ce, "ce"
          # For calls: strike < ATM is ITM
          strike_price < atm_strike
        when :pe, "pe"
          # For puts: strike > ATM is ITM
          strike_price > atm_strike
        else
          false
        end
      end

      # Log detailed filtering summary with explanations
      def log_filtering_summary(side, accepted_count, rejected_count, min_iv, max_iv, min_oi, max_spread_pct, min_delta)
        total_processed = accepted_count + rejected_count
        acceptance_rate = total_processed > 0 ? (accepted_count.to_f / total_processed * 100).round(1) : 0

        Rails.logger.info("[Options] Filtering Summary:")
        Rails.logger.info("  - Total strikes processed: #{total_processed}")
        Rails.logger.info("  - Accepted: #{accepted_count} (#{acceptance_rate}%)")
        Rails.logger.info("  - Rejected: #{rejected_count} (#{100 - acceptance_rate}%)")
        Rails.logger.info("  - Filter criteria applied:")
        Rails.logger.info("    * IV Range: #{min_iv}-#{max_iv}%")
        Rails.logger.info("    * Minimum OI: #{min_oi}")
        Rails.logger.info("    * Maximum Spread: #{max_spread_pct}%")
        Rails.logger.info("    * Minimum Delta: #{min_delta} (time-based)")

        if accepted_count == 0
          Rails.logger.warn("  - ⚠️  No strikes passed all filters - consider adjusting criteria")
        elsif accepted_count < 3
          Rails.logger.info("  - ℹ️  Limited strikes available - #{accepted_count} option(s) found")
        else
          Rails.logger.info("  - ✅ Good strike selection - #{accepted_count} options available")
        end
      end
    end
  end
end
