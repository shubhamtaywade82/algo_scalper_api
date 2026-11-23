# frozen_string_literal: true

module Options
  class ChainAnalyzer
    module StrikeScorer
      # Dynamic minimum delta thresholds depending on time of day
      # More realistic delta requirements for OTM options
      def min_delta_now
        h = Time.zone.now.hour
        return 0.15 if h >= 14 # After 2 PM - moderate delta for OTM options
        return 0.12 if h >= 13 # After 1 PM - lower delta acceptable
        return 0.10 if h >= 11 # After 11 AM - even lower delta

        0.08 # Before 11 AM - very low delta acceptable for OTM
      end

      # Dynamic ATM range based on volatility (IV rank)
      # Low volatility = tight range, High volatility = wider range
      def atm_range_pct(iv_rank = 0.5)
        case iv_rank
        when 0.0..0.2 then 0.01 # Low volatility - tight range (1%)
        when 0.2..0.5 then 0.015 # Medium volatility - medium range (1.5%)
        else 0.025 # High volatility - wider range (2.5%)
        end
      end

      # Check if a strike is ITM (In-The-Money)
      def itm_strike?(strike_price, side, atm_strike)
        case side.to_sym
        when :ce, 'ce'
          strike_price < atm_strike
        when :pe, 'pe'
          strike_price > atm_strike
        else
          false
        end
      end

      # Calculate liquidity score (0-50 based on OI with spread penalty)
      def calculate_liquidity_score(oi, _volume, spread_pct)
        score = if oi >= 1_000_000 then 50
                elsif oi >= 500_000 then 40
                elsif oi >= 100_000 then 30
                else 20
                end

        if spread_pct
          score *= 0.8 if spread_pct > 0.02 # 2%
          score *= 0.9 if spread_pct > 0.01 # 1%
        end

        score
      end

      # Calculate sophisticated strike score based on professional prop model
      def calculate_strike_score(leg, side, atm_strike, atm_range_percent, flow_score: 1.0, gamma_pressure: 0.0,
                                 prop_selector: nil, acceleration_signal: :none, history: nil)
        if prop_selector
          return score_with_prop_selector(
            leg, atm_strike, atm_range_percent,
            flow_score: flow_score, gamma_pressure: gamma_pressure,
            prop_selector: prop_selector, acceleration_signal: acceleration_signal, history: history
          )
        end

        score_with_standard_model(leg, side, atm_strike, atm_range_percent, flow_score, gamma_pressure)
      end

      private

      def score_with_prop_selector(leg, atm_strike, atm_range_percent, flow_score:, gamma_pressure:,
                                   prop_selector:, acceleration_signal:, history:)
        prop_score = prop_selector.score(leg, flow_score: flow_score, gamma_pressure: gamma_pressure, history: history)
        acceleration_boost = case acceleration_signal
                             when :strong then 0.3
                             when :moderate then 0.15
                             else 0.0
                             end

        distance_from_atm = (leg[:strike] - atm_strike).abs
        atm_range_points = atm_strike * atm_range_percent
        atm_bonus = if distance_from_atm <= (atm_range_points * 0.1) then 0.2
                    elsif distance_from_atm <= (atm_range_points * 0.3) then 0.1
                    else 0.0
                    end

        (prop_score * 100.0) + (acceleration_boost * 50.0) + (atm_bonus * 10.0)
      end

      def score_with_standard_model(leg, side, atm_strike, atm_range_percent, flow_score, gamma_pressure)
        strike_price = leg[:strike]
        oi = leg[:oi]
        spread_pct = leg[:spread] ? leg[:spread] * 100 : 0.0
        delta = leg[:delta] || 0.5

        delta_score = (1.0 - (delta - 0.5).abs) * 40.0
        liquidity_base = if oi >= 1_000_000 then 30
                         elsif oi >= 500_000 then 25
                         elsif oi >= 100_000 then 20
                         else 10
                         end
        liquidity_score = liquidity_base * [1.0 - (spread_pct / 2.0), 0.5].max
        institutional_flow_score = [flow_score / 2.0, 1.0].min * 30.0
        base_score = delta_score + liquidity_score + institutional_flow_score
        final_inst_score = base_score * (1.0 + (gamma_pressure * 0.5))

        distance_from_atm = (strike_price - atm_strike).abs
        atm_range_points = atm_strike * atm_range_percent
        atm_pref_score = if distance_from_atm <= (atm_range_points * 0.1) then 100
                         elsif distance_from_atm <= (atm_range_points * 0.3) then 80
                         elsif distance_from_atm <= (atm_range_points * 0.6) then 50
                         else 20
                         end
        atm_pref_score *= 0.7 if itm_strike?(strike_price, side, atm_strike)

        (final_inst_score * 2.0) + atm_pref_score
      end
    end
  end
end
