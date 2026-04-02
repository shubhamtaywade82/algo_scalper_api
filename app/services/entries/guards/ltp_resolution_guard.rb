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
          resolution = empty_resolution

          unless fresh_tick?(tick, max_age_seconds)
            resolution = resolve_entry_ltp(
              instrument: instrument,
              pick: pick,
              index_cfg: index_cfg,
              max_age_seconds: max_age_seconds
            )
            tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
          end

          if fresh_tick?(tick, max_age_seconds)
            log_entry_ltp_selected(index_cfg, pick, security_id, tick.ltp, 'tick_cache', tick)
            context[:ltp] = tick.ltp
            return EntryGuardPipeline::PASS
          end

          if resolution[:transport] == :websocket_fresh && resolution[:ltp].to_f.positive?
            log_entry_ltp_selected(index_cfg, pick, security_id, resolution[:ltp], 'websocket_fresh', tick)
            context[:ltp] = resolution[:ltp]
            return EntryGuardPipeline::PASS
          end

          if rest_snapshot?(resolution) && resolution[:ltp].to_f.positive?
            log_entry_ltp_selected(index_cfg, pick, security_id, resolution[:ltp], resolution[:transport].to_s, tick)
            context[:ltp] = resolution[:ltp]
            return EntryGuardPipeline::PASS
          end

          age_ms = age_ms_rounded(tick)
          ltp_probe = tick&.ltp || resolution[:ltp]
          Rails.logger.warn(
            "[EntryGuard] BLOCKED #{index_cfg[:key]} #{pick[:symbol]}: fresh_ltp_unavailable " \
            "(segment=#{segment}, security_id=#{security_id}, ltp=#{ltp_probe.inspect}, tick_age_ms=#{age_ms}, max_age_s=#{max_age_seconds})"
          )
          { blocked: "fresh_ltp_unavailable for #{index_cfg[:key]}: #{pick[:symbol]}" }
        end

        private

        def empty_resolution
          { ltp: nil, transport: :none }
        end

        def rest_snapshot?(resolution)
          %i[rest_derivative rest_instrument].include?(resolution[:transport])
        end

        def log_entry_ltp_selected(index_cfg, pick, security_id, ltp, source, tick_for_age)
          age_ms = age_ms_rounded(tick_for_age)
          ltp_label = format_ltp(ltp)
          Rails.logger.info(
            "[EntryGuard] Fresh entry LTP selected #{index_cfg[:key]} #{pick[:symbol]}: " \
            "security_id=#{security_id}, ltp=#{ltp_label}, source=#{source}, tick_age_ms=#{age_ms}"
          )
        end

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

        # Returns { ltp: BigDecimal|nil, transport: :websocket_fresh | :rest_derivative | :rest_instrument | :none }
        def resolve_entry_ltp(instrument:, pick:, index_cfg:, max_age_seconds:)
          segment = pick[:segment] || index_cfg[:segment]
          security_id = pick[:security_id]
          return empty_resolution unless segment.present? && security_id.present?

          # Strategy 1: WebSocket subscription + TickCache (only trust ticks that pass fresh_tick?)
          if Live::MarketFeedHub.instance.running? && Live::MarketFeedHub.instance.connected?
            begin
              Live::MarketFeedHub.instance.subscribe(segment: segment, security_id: security_id)
              15.times do
                sleep(0.05)
                cached_tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
                next unless cached_tick&.ltp&.to_f&.positive?
                next unless fresh_tick?(cached_tick, max_age_seconds)

                return { ltp: BigDecimal(cached_tick.ltp.to_s), transport: :websocket_fresh }
              end
            rescue StandardError
              nil
            end
          end

          # Strategy 2: REST snapshot — valid entry price even when tick cache timestamp is stale
          derivative = Derivative.find_by(id: pick[:derivative_id]) if pick[:derivative_id].present?
          if derivative
            api_ltp = derivative.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
            if api_ltp.present?
              return { ltp: BigDecimal(api_ltp.to_s), transport: :rest_derivative }
            end
          end

          api_ltp = instrument.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
          if api_ltp.present?
            return { ltp: BigDecimal(api_ltp.to_s), transport: :rest_instrument }
          end

          empty_resolution
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

        # NaN/Inf * 1000 then .round can raise FloatDomainError on some Ruby builds.
        def age_ms_rounded(tick)
          raw = tick_age_seconds(tick) * 1000.0
          return 0 unless raw.finite?

          raw.round
        rescue FloatDomainError, RangeError
          0
        end

        def format_ltp(ltp)
          f = ltp&.to_f
          f&.finite? ? f.round(2) : ltp.inspect
        end
      end
    end
  end
end
