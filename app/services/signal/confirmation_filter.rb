# frozen_string_literal: true

module Signal
  class ConfirmationFilter
    class << self
      # Filters the initial signal based on the current Last Traded Price (LTP).
      # Confirms that price action supports the signal direction before trade execution.
      #
      # @param initial_signal [Symbol] :bullish or :bearish
      # @param last_close_price [BigDecimal, Numeric] The close price (C_last) of the last completed candle
      # @param instrument [Instrument] Instrument object to fetch current LTP
      # @param index_key [String] Index key for logging context
      # @return [Hash] { confirmed: Boolean, reason: String, current_ltp: Numeric, last_close: Numeric }
      def confirm(initial_signal:, last_close_price:, instrument:, index_key:)
        Rails.logger.debug { "initial_signal: #{initial_signal}" }
        Rails.logger.debug { "last_close_price: #{last_close_price}" }
        Rails.logger.debug { "instrument: #{instrument}" }
        Rails.logger.debug { "index_key: #{index_key}" }

        unless %i[
          bullish bearish
        ].include?(initial_signal)
          return { confirmed: false, reason: 'Invalid signal direction', current_ltp: nil,
                   last_close: last_close_price }
        end

        unless last_close_price.present? && last_close_price.to_f.positive?
          return { confirmed: false, reason: 'Invalid last close price', current_ltp: nil,
                   last_close: last_close_price }
        end

        # Fetch current LTP (prioritizes WebSocket, falls back to REST API)
        current_ltp = fetch_current_ltp(instrument: instrument, index_key: index_key)

        unless current_ltp.present? && current_ltp.to_f.positive?
          Rails.logger.warn("[Signal::ConfirmationFilter] Failed to fetch LTP for #{index_key} - avoiding signal")
          return {
            confirmed: false,
            reason: 'Failed to fetch current LTP',
            current_ltp: nil,
            last_close: last_close_price
          }
        end

        # Apply confirmation logic
        confirmed = case initial_signal
                    when :bullish
                      current_ltp.to_f > last_close_price.to_f
                    when :bearish
                      current_ltp.to_f < last_close_price.to_f
                    else
                      false
                    end

        reason = if confirmed
                   case initial_signal
                   when :bullish
                     "Bullish signal CONFIRMED: LTP (#{current_ltp.round(2)}) > C_last (#{last_close_price.round(2)})"
                   when :bearish
                     "Bearish signal CONFIRMED: LTP (#{current_ltp.round(2)}) < C_last (#{last_close_price.round(2)})"
                   end
                 else
                   case initial_signal
                   when :bullish
                     "Bullish signal AVOIDED: LTP (#{current_ltp.round(2)}) <= C_last (#{last_close_price.round(2)}) - No confirmation"
                   when :bearish
                     "Bearish signal AVOIDED: LTP (#{current_ltp.round(2)}) >= C_last (#{last_close_price.round(2)}) - No confirmation"
                   end
                 end

        if confirmed
          Rails.logger.info("[Signal::ConfirmationFilter] #{index_key}: #{reason}")
        else
          Rails.logger.warn("[Signal::ConfirmationFilter] #{index_key}: #{reason}")
        end

        {
          confirmed: confirmed,
          reason: reason,
          current_ltp: current_ltp.to_f,
          last_close: last_close_price.to_f
        }
      rescue StandardError => e
        Rails.logger.error("[Signal::ConfirmationFilter] Error confirming signal for #{index_key}: #{e.class} - #{e.message}")
        {
          confirmed: false,
          reason: "Confirmation filter error: #{e.message}",
          current_ltp: nil,
          last_close: last_close_price
        }
      end

      private

      # Fetches current LTP for the instrument
      # Prioritizes WebSocket cache, falls back to REST API
      # @param instrument [Instrument] Instrument object
      # @param index_key [String] Index key for logging
      # @return [BigDecimal, Numeric, nil] Current LTP or nil if unavailable
      def fetch_current_ltp(instrument:, index_key:)
        # Strategy 1: Try WebSocket TickCache first (fastest, no API rate limits)
        hub = Live::MarketFeedHub.instance
        if hub.running? && hub.connected?
          segment = instrument.exchange_segment
          security_id = instrument.security_id.to_s

          cached_ltp = Live::TickCache.ltp(segment, security_id)
          if cached_ltp.present? && cached_ltp.to_f.positive?
            Rails.logger.debug { "[Signal::ConfirmationFilter] Got LTP from TickCache for #{index_key}: ₹#{cached_ltp}" }
            return BigDecimal(cached_ltp.to_s)
          end

          # Try subscribing and waiting briefly for a tick
          begin
            hub.subscribe(segment: segment, security_id: security_id)
            # Wait up to 200ms for tick to arrive
            4.times do
              sleep(0.05) # 50ms intervals
              cached_ltp = Live::TickCache.ltp(segment, security_id)
              if cached_ltp.present? && cached_ltp.to_f.positive?
                Rails.logger.debug { "[Signal::ConfirmationFilter] Got LTP from TickCache after subscription for #{index_key}: ₹#{cached_ltp}" }
                return BigDecimal(cached_ltp.to_s)
              end
            end
          rescue StandardError => e
            Rails.logger.debug { "[Signal::ConfirmationFilter] WebSocket subscription failed for #{index_key}: #{e.message}, falling back to API" }
          end
        end

        # Strategy 2: REST API fallback (only if WebSocket unavailable or no tick received)
        api_ltp = instrument.fetch_ltp_from_api_for_segment(
          segment: instrument.exchange_segment,
          security_id: instrument.security_id
        )

        if api_ltp.present? && api_ltp.to_f.positive?
          Rails.logger.debug { "[Signal::ConfirmationFilter] Got LTP from API for #{index_key}: ₹#{api_ltp}" }
          return BigDecimal(api_ltp.to_s)
        end

        Rails.logger.warn("[Signal::ConfirmationFilter] Failed to fetch LTP for #{index_key} via all methods")
        nil
      rescue StandardError => e
        Rails.logger.error("[Signal::ConfirmationFilter] Error fetching LTP for #{index_key}: #{e.class} - #{e.message}")
        nil
      end
    end
  end
end
