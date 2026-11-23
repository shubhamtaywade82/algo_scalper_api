# frozen_string_literal: true

module Options
  class ChainAnalyzer
    module LegacyFilters
      private

      def calculate_strike_interval
        self.class.strike_interval(@sorted_strikes || [])
      end

      def find_atm_strike(spot, interval)
        return spot unless interval&.positive?

        (spot / interval).round * interval
      end

      def generate_candidate_strikes(atm_strike, interval, option_type, strike_config)
        include_atm = strike_config[:include_atm] != false
        max_otm = strike_config[:max_otm] || 2
        candidates = []
        candidates << atm_strike if include_atm && @sorted_strikes.include?(atm_strike)

        1.upto(max_otm) do |i|
          strike = option_type == 'ce' ? atm_strike + (i * interval) : atm_strike - (i * interval)
          candidates << strike if @sorted_strikes.include?(strike)
        end

        candidates.uniq.sort
      end

      def filter_strikes(candidates, option_type)
        candidates.filter_map do |strike|
          option_data = get_option_data(strike, option_type)
          next nil unless option_data
          next nil unless passes_liquidity_filter?(option_data)
          next nil unless passes_volatility_filter?(option_data, strike)
          next nil unless passes_delta_filter?(option_data)

          { strike: strike, option_data: option_data }
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

        strike_interval = calculate_strike_interval
        atm_strike = find_atm_strike(@spot_price, strike_interval)

        min_iv_threshold = if strike == atm_strike then [5.0, thresholds[:min_iv] * 0.6].max
                           elsif (strike - atm_strike).abs <= strike_interval then [7.0, thresholds[:min_iv] * 0.8].max
                           else thresholds[:min_iv]
                           end

        iv.between?(min_iv_threshold, thresholds[:max_iv])
      end

      def passes_delta_filter?(option_data)
        thresholds = @config[:delta_filter]
        delta = option_data.dig('greeks', 'delta')&.to_f&.abs
        return false unless delta

        min_delta = thresholds[:time_based] ? self.class.min_delta_now : thresholds[:min_delta]
        delta >= min_delta
      end

      def score_strikes(filtered, atm_strike, option_type)
        calculate_strike_interval
        atm_range_percent = self.class.atm_range_pct(0.5)

        # rubocop:disable-next Style/MultilineBlockChain
        filtered.map do |item|
          strike = item[:strike]
          option_data = item[:option_data]
          iv = option_data['implied_volatility']&.to_f
          delta = option_data.dig('greeks', 'delta')&.to_f&.abs
          delta ||= Options::Greeks::Calculator.estimate_delta(
            spot_price: spot_price, strike_price: strike, option_type: option_type,
            iv_pct: iv, expiry_date: expiry_date
          )

          leg = {
            strike: strike, ltp: option_data['last_price']&.to_f, iv: iv, oi: option_data['oi']&.to_i,
            spread: calculate_spread_ratio(option_data), delta: delta, distance_from_atm: (strike - atm_strike).abs
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

        strike_data = @chain_data[:oc][strike.to_f.to_s]
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
    end
  end
end
