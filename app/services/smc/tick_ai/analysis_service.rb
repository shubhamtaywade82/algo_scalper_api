# frozen_string_literal: true

module Smc
  module TickAi
    # Registers a lightweight +MarketFeedHub+ tick callback (trading daemon only).
    class AnalysisService
      def initialize(hub: Live::MarketFeedHub.instance)
        @hub = hub
        @running = false
      end

      def start
        @running = true
        unless feature_enabled?
          Rails.logger.info('[Smc::TickAi::AnalysisService] Disabled (signals.tick_ai_analysis_enabled)')
          return
        end

        @hub.on_tick { |tick| handle_tick(tick) }
        Rails.logger.info('[Smc::TickAi::AnalysisService] on_tick callback registered')
      end

      def stop
        @running = false
        Rails.logger.info('[Smc::TickAi::AnalysisService] Stopped')
      end

      private

      def feature_enabled?
        AlgoConfig.fetch.dig(:signals, :tick_ai_analysis_enabled) == true
      rescue StandardError
        false
      end

      def handle_tick(tick)
        return unless @running
        return unless feature_enabled?

        sid = tick[:security_id].to_s
        return if sid.blank?
        return unless index_entry_for_sid(sid)

        ltp = tick[:ltp].to_f
        return unless ltp.positive?

        ttl = (AlgoConfig.fetch.dig(:signals, :tick_ai_min_interval_seconds) || 15).to_i
        return unless Gate.acquire(sid, ttl_seconds: ttl)

        entry = index_entry_for_sid(sid)
        instrument = Instrument.find_by(security_id: sid)
        unless instrument&.exchange_segment.to_s == entry[:segment].to_s
          Rails.logger.debug { "[Smc::TickAi::AnalysisService] No index Instrument for #{sid}" }
          return
        end

        Smc::TickAiDigestJob.perform_later(
          instrument_id: instrument.id,
          ltp: ltp,
          tick_at: Time.current.iso8601
        )
      rescue StandardError => e
        Rails.logger.warn("[Smc::TickAi::AnalysisService] #{e.class} - #{e.message}")
      end

      def index_entry_for_sid(sid)
        @index_by_sid ||= {}
        return @index_by_sid[sid] if @index_by_sid.key?(sid)

        @index_by_sid[sid] = IndexConfigLoader.load_indices.find { |c| c[:sid].to_s == sid }
      end
    end
  end
end
