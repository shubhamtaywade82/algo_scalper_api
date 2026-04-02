# frozen_string_literal: true

module Ai
  # Assembles a compact Ollama prompt for on-demand AI market snapshots.
  #
  # Pure function — all context is passed in, no I/O.
  # All params are optional; the prompt degrades gracefully with nil inputs.
  #
  # Returns an Array of { role: String, content: String } hashes
  # for direct use with Services::Ai::OllamaClient.instance.chat(messages: [...])
  class AiSnapshotPromptBuilder
    SYSTEM_PROMPT = <<~SYSTEM.strip
      You are a concise intraday options trading assistant for Indian index markets.
      Given current market context, provide a brief trading outlook in 3-5 bullet points.
      Focus on: trend direction, key risk levels, and whether conditions favour entry.
      Be direct, specific, and quantitative where possible. Avoid generic statements.
    SYSTEM

    def self.build(index_key:, ltp:, smc:, regime:, calibration_stats:)
      user_content = build_user_prompt(
        index_key: index_key.to_s.upcase,
        ltp: ltp,
        smc: smc,
        regime: regime,
        calibration_stats: calibration_stats
      )

      [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user',   content: user_content }
      ]
    end

    def self.build_user_prompt(index_key:, ltp:, smc:, regime:, calibration_stats:)
      session_context = TradingSession::Service.market_closed? ? 'After market hours' : 'Market open'

      lines = ["## #{index_key} Snapshot Request — #{Time.current.strftime('%Y-%m-%d %H:%M IST')}"]
      lines << "Session: #{session_context}"
      lines << "LTP: #{ltp || 'unavailable'}"
      lines << ''

      if smc.present?
        lines << '### Market Structure (SMC)'
        smc.each { |k, v| lines << "- #{k}: #{v}" }
        lines << ''
      end

      if regime.present?
        lines << '### Market Regime'
        regime.each { |k, v| lines << "- #{k}: #{v}" }
        lines << ''
      end

      if calibration_stats.present?
        lines << '### Historical Options Stats (last calibration)'
        lines << "- Avg gain: #{calibration_stats['avg_gain']}%"
        lines << "- Avg retrace: #{calibration_stats['avg_retrace_abs']}%"
        lines << "- Avg loss: #{calibration_stats['avg_loss_abs']}%" if calibration_stats['avg_loss_abs']
        lines << ''
      end

      lines << 'Provide a brief trading outlook based on the above context.'
      lines.join("\n")
    end

    private_class_method :build_user_prompt
  end
end
