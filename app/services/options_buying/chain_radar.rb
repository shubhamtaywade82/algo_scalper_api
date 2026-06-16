# frozen_string_literal: true

module OptionsBuying
  class ChainRadar
    def self.scan!(index_key)
      new(index_key).scan!
    end

    def initialize(index_key)
      @index_key = index_key.to_s.upcase
    end

    def scan!
      return unless Mode.chain_radar_enabled?

      analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key)
      spot = analyzer.spot_ltp
      return unless spot&.positive?

      bullish = analyzer.select_candidates(limit: 50, direction: :bullish)
      bearish = analyzer.select_candidates(limit: 50, direction: :bearish)
      all = (bullish + bearish).uniq { |c| c[:security_id] }
      ce = all.select { |c| c[:type].to_s.upcase == 'CE' }
      pe = all.select { |c| c[:type].to_s.upcase == 'PE' }

      liquid = filter_liquid(all, spot: spot)
      resistance_strike = max_oi_strike(ce) # call wall above spot — bullish breakout level
      support_strike = max_oi_strike(pe)    # put wall below spot — bearish breakdown level

      StateStore.set_radar_strikes(@index_key, liquid)
      StateStore.set_resistance(@index_key, resistance_strike) if resistance_strike&.positive?
      StateStore.set_support(@index_key, support_strike) if support_strike&.positive?

      liquid.each do |strike|
        vol = strike[:volume].to_i
        next unless vol.positive?

        rate_per_minute = vol.to_f / session_minutes_elapsed
        StateStore.set_volume_rate_baseline(strike[:security_id], rate_per_minute)
      end

      OptionsBuying::RsiDivergenceScanner.scan!(index_key: @index_key)

      Rails.logger.info(
        "[ChainRadar] #{@index_key} spot=#{spot.round(2)} resistance=#{resistance_strike} " \
        "support=#{support_strike} liquid=#{liquid.size}"
      )

      { index_key: @index_key, spot: spot, resistance: resistance_strike, support: support_strike,
        strikes: liquid.size }
    rescue StandardError => e
      Rails.logger.error("[ChainRadar] #{@index_key} #{e.class} - #{e.message}")
      nil
    end

    private

    def radar_config
      Mode.config[:chain_radar] || {}
    end

    def filter_liquid(candidates, spot:)
      delta_min = (radar_config[:delta_min] || 0.45).to_f
      delta_max = (radar_config[:delta_max] || 0.55).to_f
      min_volume = (radar_config[:min_volume] || 10_000).to_i
      strike_step = strike_step_for(spot)

      candidates.filter_map do |candidate|
        delta = candidate[:delta].to_f.abs
        delta = atm_delta_fallback(candidate[:strike], spot, strike_step) if delta.zero?

        volume = candidate[:volume].to_i
        liquidity = volume.positive? ? volume : candidate[:oi].to_i
        next unless delta.between?(delta_min, delta_max)
        next unless liquidity >= min_volume

        {
          security_id: candidate[:security_id],
          segment: candidate[:segment],
          strike: candidate[:strike],
          type: candidate[:type].to_s.upcase,
          delta: candidate[:delta],
          volume: volume.positive? ? volume : candidate[:oi].to_i,
          oi: candidate[:oi]
        }
      end
    end

    # Peak open-interest strike among the given (already type-filtered) candidates.
    def max_oi_strike(candidates)
      with_oi = candidates.select { |c| c[:oi].to_i.positive? }
      with_oi.max_by { |c| c[:oi].to_i }&.dig(:strike)&.to_f
    end

    def session_minutes_elapsed
      market_open = Time.zone.parse("#{Time.zone.today} 09:15")
      elapsed = ((Time.current - market_open) / 60.0).floor
      [elapsed, 1].max
    end

    def strike_step_for(spot)
      return 50 unless spot&.positive?

      spot >= 50_000 ? 100 : 50
    end

    def atm_delta_fallback(strike, spot, strike_step)
      return 0.0 unless spot&.positive? && strike&.positive? && strike_step.positive?

      atm = (spot / strike_step).round * strike_step
      (strike.to_f - atm).abs <= (strike_step * 2) ? 0.5 : 0.0
    end
  end
end
