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

      target_expiry = determine_target_expiry
      analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key, expiry: target_expiry)
      spot = analyzer.spot_ltp
      return unless spot&.positive?

      bullish = analyzer.select_candidates(limit: 50, direction: :bullish)
      bearish = analyzer.select_candidates(limit: 50, direction: :bearish)
      all = (bullish + bearish).uniq { |c| c[:security_id] }
      ce = all.select { |c| c[:type].to_s.upcase == 'CE' }
      pe = all.select { |c| c[:type].to_s.upcase == 'PE' }

      liquid = filter_liquid(all, spot: spot)
      resistance_strike = structural_strike(ce, spot: spot, side: :resistance)
      support_strike = structural_strike(pe, spot: spot, side: :support)

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

    def determine_target_expiry
      config = Mode.config[:expiry] || {}
      return nil unless config[:prefer_monthly]

      min_dte = (Mode.positional_active? ? config[:positional_min_dte] : config[:min_dte]) || 7

      idx_cfg = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
      return nil unless idx_cfg

      instrument = IndexInstrumentCache.instance.get_or_fetch(idx_cfg)
      return nil unless instrument

      expiry_list = instrument.expiry_list
      return nil unless expiry_list&.any?

      today = Time.zone.today
      valid_dates = expiry_list.filter_map do |raw|
        if raw.is_a?(String)
  begin
                              Date.parse(raw)
  rescue StandardError
                              nil
  end
        else
  raw.try(:to_date)
        end
      end

      valid_dates.select { |d| d >= today && (d - today).to_i >= min_dte }.min
    rescue StandardError => e
      Rails.logger.warn("[ChainRadar] determine_target_expiry failed: #{e.message}")
      nil
    end

    def radar_config
      Mode.config[:chain_radar] || {}
    end

    def filter_liquid(candidates, spot:)
      delta_min = (radar_config[:delta_min] || 0.45).to_f
      delta_max = (radar_config[:delta_max] || 0.55).to_f
      min_volume = (radar_config[:min_volume] || 10_000).to_i
      strike_step = strike_step_for(spot)
      liquidity_data_available = candidates.any? do |candidate|
        candidate[:volume].to_i.positive? || candidate[:oi].to_i.positive?
      end

      unless liquidity_data_available
        Rails.logger.info(
          "[ChainRadar] #{@index_key} no OI/volume in chain — using LTP+delta fallback for radar strikes"
        )
      end

      candidates.filter_map do |candidate|
        delta = candidate[:delta].to_f.abs
        delta = atm_delta_fallback(candidate[:strike], spot, strike_step) if delta.zero?

        volume = candidate[:volume].to_i
        liquidity = volume.positive? ? volume : candidate[:oi].to_i
        next unless delta.between?(delta_min, delta_max)
        next unless liquid_enough?(candidate, liquidity, min_volume, liquidity_data_available)

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

    def liquid_enough?(candidate, liquidity, min_volume, liquidity_data_available)
      return true if liquidity >= min_volume
      return false if liquidity_data_available

      candidate[:ltp].to_f.positive?
    end

    # Call wall (CE) at/above spot; put wall (PE) at/below spot. Uses peak OI when
    # available, otherwise the spot-side strike nearest to the index LTP.
    def structural_strike(candidates, spot:, side:)
      return nil unless spot&.positive? && candidates.any?

      pool = candidates_for_side(candidates, spot: spot, side: side)
      with_oi = pool.select { |c| c[:oi].to_i.positive? }
      if with_oi.any?
        return with_oi.max_by { |c| c[:oi].to_i }&.dig(:strike)&.to_f
      end

      pool.min_by { |c| (c[:strike].to_f - spot.to_f).abs }&.dig(:strike)&.to_f
    end

    def candidates_for_side(candidates, spot:, side:)
      spot_f = spot.to_f
      case side
      when :resistance
        above = candidates.select { |c| c[:strike].to_f >= spot_f }
        above.presence || candidates
      when :support
        below = candidates.select { |c| c[:strike].to_f <= spot_f }
        below.presence || candidates
      else
        candidates
      end
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
