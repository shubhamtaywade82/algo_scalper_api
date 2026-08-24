# frozen_string_literal: true

module Entries
  module Guards
    class LtpResolutionGuard
      DEFAULT_ENTRY_LTP_MAX_AGE_SECONDS = 2.0

      class << self
        def call(context)
          pick = context[:pick]
          instrument = context[:instrument]
          index_cfg = context[:index_cfg]
          segment = pick[:segment] || index_cfg[:segment]
          security_id = pick[:security_id]
          max_age_seconds = entry_ltp_max_age_seconds

          # Log WebSocket status but never block
          hub = Live::MarketFeedHub.instance
          unless hub.running? && hub.connected?
            Rails.logger.info('[EntryGuard] WebSocket not connected - will use REST API fallback for LTP')
          end

          tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
          source = 'tick_cache'
          ltp = tick&.ltp

          unless fresh_tick?(tick, max_age_seconds)
            resolved = EntryGuard.resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg)
            tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
            source = 'forced_refresh'
            ltp = tick&.ltp || resolved
          end

          unless fresh_tick?(tick, max_age_seconds)
            age_ms = tick_age_ms(tick)
            Rails.logger.warn(
              "[EntryGuard] BLOCKED #{index_cfg[:key]} #{pick[:symbol]}: fresh_ltp_unavailable " \
              "(segment=#{segment}, security_id=#{security_id}, ltp=#{ltp.inspect}, tick_age_ms=#{age_ms}, max_age_s=#{max_age_seconds})"
            )
            return { blocked: "fresh_ltp_unavailable for #{index_cfg[:key]}: #{pick[:symbol]}" }
          end

          age_ms = tick_age_ms(tick)
          Rails.logger.info(
            "[EntryGuard] Fresh entry LTP selected #{index_cfg[:key]} #{pick[:symbol]}: " \
            "security_id=#{security_id}, ltp=#{tick.ltp.to_f.round(2)}, source=#{source}, tick_age_ms=#{age_ms}"
          )

          context[:ltp] = tick.ltp
          EntryGuardPipeline::PASS
        end

        private

        def entry_ltp_max_age_seconds
          cfg = AlgoConfig.fetch
          value = cfg.dig(:realtime, :entry_ltp_max_age_seconds).to_f
          value.positive? ? value : DEFAULT_ENTRY_LTP_MAX_AGE_SECONDS
        rescue StandardError
          DEFAULT_ENTRY_LTP_MAX_AGE_SECONDS
        end

        def fresh_tick?(tick, max_age_seconds)
          return false unless tick&.ltp&.to_f&.positive?

          tick_age_seconds(tick) <= max_age_seconds
        end

        def tick_age_seconds(tick)
          return Float::INFINITY unless tick&.timestamp

          ts = tick.timestamp
          tick_time = if ts.respond_to?(:to_time)
                        ts.to_time
                      elsif ts.is_a?(Numeric)
                        Time.at(ts.to_f)
                      end
          return Float::INFINITY unless tick_time

          (Time.current - tick_time).to_f
        rescue StandardError
          Float::INFINITY
        end

        def tick_age_ms(tick)
          age_seconds = tick_age_seconds(tick)
          return -1 unless age_seconds.finite?

          (age_seconds * 1000.0).round
        end
      end
    end
  end
end
