# frozen_string_literal: true

module Smc
  module Confluence
    # Single LTF candle fetch + last-bar {Engine} result (for gating and metadata).
    module LtfSnapshot
      SUMMARY_KEYS = %w[long_score short_score long_signal short_signal structure_bias].freeze

      module_function

      # @return [Hash] :interval, :last (BarResult or nil), :summary (Hash or nil), optional :error
      def fetch(instrument:, signals_cfg: {})
        interval = ltf_interval_from(signals_cfg)
        rows = CandleRows.from_series(instrument.candles(interval: interval))
        return { interval: interval, last: nil, summary: nil } if rows.size < 10

        last = Engine.run(rows).last
        summary = last&.serialize&.slice(*SUMMARY_KEYS)
        { interval: interval, last: last, summary: summary }
      rescue StandardError => e
        Rails.logger.warn("[Smc::Confluence::LtfSnapshot] #{e.class} - #{e.message}")
        { interval: ltf_interval_from(signals_cfg), last: nil, summary: nil, error: e.message }
      end

      # @param snap [Hash] from {.fetch}
      # @return [Boolean] true when gate passes or data missing (fail-open)
      def gate_passes?(final_direction, snap)
        last = snap[:last]
        return true if last.nil?

        case final_direction
        when :bullish
          last.long_signal == true
        when :bearish
          last.short_signal == true
        else
          true
        end
      end

      def ltf_interval_from(signals_cfg)
        raw = signals_cfg[:smc_confluence_intervals] || signals_cfg['smc_confluence_intervals'] || {}
        (raw[:ltf] || raw['ltf'] || Smc::BiasEngine::LTF_INTERVAL).to_s
      end
    end
  end
end
