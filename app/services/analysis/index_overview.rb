# frozen_string_literal: true

module Analysis
  # The payload behind GET /api/analysis/:index_key: stored analysis, live price, session flags and
  # a config summary for one index. Built from cache reads only, so it answers instantly.
  class IndexOverview
    attr_reader :stale_components

    def initialize(index_key:, instrument:)
      @index_key = index_key
      @instrument = instrument
      # Read when the request arrives, before the caller starts any refresh that rewrites the store.
      @stored = AnalysisStore.read_all(index_key)
      @stale_components = AnalysisStore.stale_components(index_key)
    end

    # @return [Hash] JSON-ready payload
    def to_h
      header.merge(stored_analysis).merge(context)
    end

    private

    def header
      ltp = Live::TickCache.ltp(@instrument.exchange_segment, @instrument.security_id)

      {
        index_key: @index_key,
        symbol: @instrument.symbol_name,
        ltp: ltp&.to_f,
        timestamp: Time.current.iso8601,
        session: {
          market_closed: TradingSession::Service.market_closed?,
          generative_ai_gated: Ai::GenerativeAiMarketGate.skip?(force: false)
        }
      }
    end

    def stored_analysis
      {
        smc: @stored[:smc]&.dig(:data), smc_validity: @stored[:smc]&.dig(:validity),
        ai_analysis: @stored[:ai]&.dig(:data), ai_validity: @stored[:ai]&.dig(:validity),
        market_regime: @stored[:regime]&.dig(:data), regime_validity: @stored[:regime]&.dig(:validity)
      }
    end

    def context
      {
        time_regime: safe_call('time_regime') { Live::TimeRegimeService.instance.current_regime },
        active_positions: PositionTracker.active.where("meta->>'index_key' = ?", @index_key).count,
        config: config_summary,
        background_refresh: refresh_status
      }
    end

    def refresh_status
      return nil if @stale_components.empty?

      { refreshing: @stale_components, message: 'Background refresh triggered' }
    end

    def config_summary
      cfg = AlgoConfig.fetch
      risk = cfg[:risk] || {}
      index_cfg = (cfg[:indices] || []).find { |i| i[:key] == @index_key } || {}

      {
        trailing: risk.dig(:institutional_trailing, @index_key.downcase.to_sym),
        time_stop: risk[:time_stop],
        profit_floor: risk[:profit_floor],
        risk_model: index_cfg[:risk_model],
        direction: index_cfg[:direction]
      }
    end

    def safe_call(label)
      yield
    rescue StandardError => e
      Rails.logger.warn("[Analysis::IndexOverview] #{label} failed: #{e.class} - #{e.message}")
      nil
    end
  end
end
