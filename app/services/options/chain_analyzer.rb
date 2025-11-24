# frozen_string_literal: true

require 'bigdecimal'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'

module Options
  class ChainAnalyzer
    DEFAULT_DIRECTION = :bullish

    def initialize(index:, data_provider:, config: {})
      @index_cfg = normalize_index(index)
      @provider = data_provider
      @config = config || {}
    end

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
        analyzer_config: @config.presence
      ).compact
    end

    def fetch_spot
      return unless @provider.respond_to?(:underlying_spot)

      @provider.underlying_spot(@index_cfg[:key])
    rescue StandardError => e
      Rails.logger.debug { "[Options::ChainAnalyzer] Spot fetch failed: #{e.class} - #{e.message}" }
      nil
    end

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

      def filter_and_rank_from_instrument_data(option_chain_data, atm:, side:, index_cfg:, expiry_date:, instrument:)
        # Force reload - debugging index_cfg scope issue
        return [] unless option_chain_data

        # Rails.logger.debug { "[Options] Method called with index_cfg: #{index_cfg[:key]}, expiry_date: #{expiry_date}" }

        # Rails.logger.debug { "[Options] Processing #{option_chain_data.size} strikes for #{side} options" }

        # Calculate strike interval dynamically from available strikes
        strikes = option_chain_data.keys.map(&:to_f).sort
        oc_strikes = strikes # Make strikes available for ATM range calculation

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

        # For buying options, focus on ATM and nearby strikes only (+-1,2,3 steps)
        # This prevents selecting expensive ITM options or far OTM options
        target_strikes = if [:ce, 'ce'].include?(side)
                           # CE: ATM, ATM+1, ATM+2, ATM+3 (OTM calls)
                           [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval),
                            atm_strike + (3 * strike_interval)]
                             .select do |s|
                             oc_strikes.include?(s)
                           end
                             .first(3) # Limit to top 3 strikes
                         else
                           # PE: ATM, ATM-1, ATM-2, ATM-3 (OTM puts)
                           [atm_strike, atm_strike - strike_interval, atm_strike - (2 * strike_interval),
                            atm_strike - (3 * strike_interval)]
                             .select do |s|
                             oc_strikes.include?(s)
                           end
                             .first(3) # Limit to top 3 strikes
                         end

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

          derivative_scope =
            if instrument.respond_to?(:derivatives) && instrument.derivatives.present?
              instrument.derivatives
            elsif instrument.persisted?
              instrument.derivatives
            end

          derivative = if derivative_scope
                         Array(derivative_scope).detect do |d|
                           d.expiry_date == expiry_date_obj &&
                             d.option_type == option_type &&
                             BigDecimal(d.strike_price.to_s) == strike_bd
                         end
                       else
                         # Fall back to querying the Derivative model when association is unavailable
                         Derivative.where(
                           underlying_symbol: instrument.symbol_name,
                           exchange: instrument.exchange,
                           segment: instrument.segment,
                           expiry_date: expiry_date_obj,
                           option_type: option_type
                         ).detect do |d|
                           BigDecimal(d.strike_price.to_s) == strike_bd
                         end
                       end

          security_id = if derivative
                          derived_id = derivative.security_id.to_s
                          valid_security_id?(derived_id) ? derived_id : nil
                        end

          if security_id.blank?
            fallback_id = Derivative.find_security_id(
              underlying_symbol: index_cfg[:key],
              strike_price: strike,
              expiry_date: expiry_date_obj,
              option_type: option_type
            )
            security_id = fallback_id if valid_security_id?(fallback_id)
          end

          unless security_id.present?
            Rails.logger.debug do
              "[Options::ChainAnalyzer] Skipping #{index_cfg[:key]} #{strike} #{side} - " \
                "missing tradable security_id (found=#{derivative&.security_id})"
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
        case iv_rank
        when 0.0..0.2 then 'Low'
        when 0.2..0.5 then 'Medium'
        else 'High'
        end

        if [:ce, 'ce'].include?(side)
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
