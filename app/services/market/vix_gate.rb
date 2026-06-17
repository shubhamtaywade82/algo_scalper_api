# frozen_string_literal: true

module Market
  # India VIX pre-market and intraday gate for index options buying.
  # Blocks new entries above entry_ceiling; tick/5s paths force-exit above force_exit_above.
  class VixGate
    CACHE_LTP_KEY = 'market:vix_gate:ltp'
    CACHE_TS_KEY = 'market:vix_gate:ts'
    ENTRY_ALLOWED_KEY = 'market:vix_gate:entry_allowed'
    FORCE_EXIT_KEY = 'market:vix_gate:force_exit'

    class << self
      def evaluate!
        return unless enabled?

        vix = fetch_ltp
        unless vix&.positive?
          Rails.logger.warn('[VixGate] Failed to fetch India VIX LTP')
          return nil
        end

        write_ltp!(vix)
        apply_gates!(vix)
        vix
      rescue StandardError => e
        Rails.logger.error("[VixGate] evaluate! #{e.class} - #{e.message}")
        nil
      end

      def entry_allowed?
        return true unless enabled?

        Rails.cache.read(ENTRY_ALLOWED_KEY) != false
      rescue StandardError
        true
      end

      def force_exit_active?
        return false unless enabled?

        Rails.cache.read(FORCE_EXIT_KEY) == true
      rescue StandardError
        false
      end

      def current_ltp
        val = Rails.cache.read(CACHE_LTP_KEY)
        val&.to_f
      rescue StandardError
        nil
      end

      private

      def enabled?
        config[:enabled] == true
      end

      def config
        AlgoConfig.fetch.dig(:market, :vix_gate) || {}
      rescue StandardError
        {}
      end

      def entry_ceiling
        (config[:entry_ceiling] || 20.0).to_f
      end

      def force_exit_above
        (config[:force_exit_above] || 22.0).to_f
      end

      def fetch_ltp
        segment = config[:segment].to_s.presence || 'IDX_I'
        security_id = config[:security_id].to_s.presence
        return nil if security_id.blank?

        cached = Live::TickCache.ltp(segment, security_id)
        return cached.to_f if cached&.to_f&.positive?

        instrument = Instrument.find_by_sid_and_segment(
          security_id: security_id,
          segment_code: segment
        )
        return nil unless instrument

        instrument.resolve_ltp(segment: segment, security_id: security_id)&.to_f
      rescue StandardError => e
        Rails.logger.warn("[VixGate] fetch_ltp #{e.class} - #{e.message}")
        nil
      end

      def write_ltp!(vix)
        Rails.cache.write(CACHE_LTP_KEY, vix, expires_in: 30.minutes)
        Rails.cache.write(CACHE_TS_KEY, Time.current.to_i, expires_in: 30.minutes)
      end

      def apply_gates!(vix)
        if vix > force_exit_above
          Rails.cache.write(ENTRY_ALLOWED_KEY, false, expires_in: 30.minutes)
          Rails.cache.write(FORCE_EXIT_KEY, true, expires_in: 30.minutes)
          Rails.logger.warn(
            "[VixGate] VIX=#{vix.round(2)} above force_exit #{force_exit_above} — entries locked, force-exit armed"
          )
        elsif vix > entry_ceiling
          Rails.cache.write(ENTRY_ALLOWED_KEY, false, expires_in: 30.minutes)
          Rails.cache.write(FORCE_EXIT_KEY, false, expires_in: 30.minutes)
          Rails.logger.warn(
            "[VixGate] VIX=#{vix.round(2)} above entry ceiling #{entry_ceiling} — new entries locked"
          )
        else
          Rails.cache.write(ENTRY_ALLOWED_KEY, true, expires_in: 30.minutes)
          Rails.cache.write(FORCE_EXIT_KEY, false, expires_in: 30.minutes)
          Rails.logger.info("[VixGate] VIX=#{vix.round(2)} — entry allowed")
        end
      end
    end
  end
end
