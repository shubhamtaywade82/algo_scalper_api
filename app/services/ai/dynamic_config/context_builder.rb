# frozen_string_literal: true

module Ai
  module DynamicConfig
    # Live regime + option-chain + risk snapshot for one index, feeding
    # DynamicConfigAgent's prompt. Read-only — same instrument/chain lookups
    # MarketAnalysisAgent and Options::ChainAnalyzer already use elsewhere.
    class ContextBuilder
      REGIME_INTERVAL = '15'

      def self.call(index_key:)
        new(index_key: index_key).call
      end

      def initialize(index_key:)
        @index_key = index_key.to_s.upcase
      end

      def call
        {
          index_key: @index_key,
          regime: regime_snapshot,
          chain: chain_snapshot,
          risk: risk_snapshot,
          current_config: current_config_slice
        }
      end

      private

      def index_cfg
        @index_cfg ||= IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
      end

      def instrument
        return nil unless index_cfg

        @instrument ||= IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      end

      def regime_snapshot
        return nil unless instrument

        series = instrument.candle_series(interval: REGIME_INTERVAL)
        return nil if series.blank? || series.candles.empty?

        snapshot = MarketContext::RegimeComposer.new(series: series, index_key: @index_key).call
        {
          structure: snapshot.structure,
          strength: snapshot.strength,
          volatility_state: snapshot.volatility_state,
          participation: snapshot.participation,
          conviction_score: snapshot.conviction_score
        }
      rescue StandardError => e
        Rails.logger.warn("[Ai::DynamicConfig::ContextBuilder] regime_snapshot failed: #{e.message}")
        nil
      end

      def chain_snapshot
        return nil unless index_cfg

        analyzer = Options::ChainAnalyzer.new(index: index_cfg)
        return nil unless analyzer.load_chain_data!

        summary = analyzer.chain_summary
        atm = summary[:atm_strike]
        {
          spot_price: summary[:spot_price],
          atm_strike: atm,
          ce: strike_snapshot(analyzer, atm, 'ce'),
          pe: strike_snapshot(analyzer, atm, 'pe')
        }
      rescue StandardError => e
        Rails.logger.warn("[Ai::DynamicConfig::ContextBuilder] chain_snapshot failed: #{e.message}")
        nil
      end

      def strike_snapshot(analyzer, atm_strike, option_type)
        return nil unless atm_strike

        data = analyzer.analyze_strike(atm_strike, option_type)
        return nil unless data

        data.slice(:last_price, :iv, :oi, :volume, :volatility_assessment, :liquidity_status)
      end

      def risk_snapshot
        exited_today = PositionTracker.exited.where(exited_at: Time.current.beginning_of_day..).order(exited_at: :desc)
        {
          circuit_breaker_tripped: Risk::CircuitBreaker.instance.tripped?,
          today_realized_pnl_rupees: exited_today.sum { |t| t.last_pnl_rupees.to_f }.round(2),
          recent_consecutive_losses: exited_today.first(5).map { |t| t.last_pnl_rupees.to_f }.take_while(&:negative?).size
        }
      rescue StandardError => e
        Rails.logger.warn("[Ai::DynamicConfig::ContextBuilder] risk_snapshot failed: #{e.message}")
        # Fail closed: an unknown risk state must read as stressed, not safe — this only
        # feeds DynamicConfigAgent's stress gate, never a live trading decision directly.
        { circuit_breaker_tripped: true, today_realized_pnl_rupees: 0.0, recent_consecutive_losses: 0 }
      end

      def current_config_slice
        return {} unless index_cfg

        risk = AlgoConfig.fetch[:risk] || {}
        {
          capital_alloc_pct: index_cfg[:capital_alloc_pct],
          risk_model: index_cfg[:risk_model],
          adx_thresholds: index_cfg[:adx_thresholds],
          premium_band: index_cfg[:premium_band],
          cooldown_sec: index_cfg[:cooldown_sec],
          max_trades_per_day: index_cfg.dig(:trade_limits, :max_trades_per_day),
          sl_pct: risk[:sl_pct],
          tp_pct: risk[:tp_pct]
        }
      end
    end
  end
end
