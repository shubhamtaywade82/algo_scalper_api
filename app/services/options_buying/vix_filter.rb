# frozen_string_literal: true

module OptionsBuying
  # VIX Integration tailored for Options Buying
  class VixFilter
    CACHE_KEY_PERCENTILE = 'market:vix_gate:percentile_20d'

    def valid_for_buying?
      return true unless enabled?

      vix = current_vix
      return false unless vix&.positive?

      # VIX floor check
      if vix < vix_min_for_buying
        Rails.logger.info("[VixFilter] VIX #{vix} < floor #{vix_min_for_buying}. Blocked.")
        return false
      end

      # VIX ceiling check
      if vix > vix_max_for_buying
        Rails.logger.info("[VixFilter] VIX #{vix} > ceiling #{vix_max_for_buying}. Blocked.")
        return false
      end

      # VIX crush check
      if vix_dropping_intraday?(vix)
        Rails.logger.info("[VixFilter] VIX dropping > #{vix_drop_max_pct * 100}%. Blocked.")
        return false
      end

      true
    end

    def current_vix
      Market::VixGate.current_ltp
    end

    def current_percentile
      val = Rails.cache.read(CACHE_KEY_PERCENTILE)
      val&.to_f
    end

    private

    def enabled?
      Mode.config.dig(:vix_filter, :enabled) == true
    end

    def config
      Mode.config[:vix_filter] || {}
    end

    def vix_min_for_buying
      (config[:vix_min_for_buying] || 12.0).to_f
    end

    def vix_max_for_buying
      (config[:vix_max_for_buying] || 30.0).to_f
    end

    def vix_drop_max_pct
      (config[:vix_drop_max_pct] || 0.05).to_f
    end

    def vix_dropping_intraday?(current)
      # Uses daily open of VIX. If unavailable, skips check.
      vix_open = Live::TickCache.open_price('IDX_I', '26009') # INDIA VIX sid
      return false unless vix_open&.positive?

      drop_pct = (vix_open - current) / vix_open
      drop_pct > vix_drop_max_pct
    end
  end
end
