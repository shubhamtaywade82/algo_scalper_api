# frozen_string_literal: true

module Ai
  # Central guard for Ollama-backed "generative" AI when the cash session is closed.
  #
  # Event-only paths (e.g. tick SMC) still get cheap suppression here so queued jobs
  # after the bell do not burn GPU/API. Toggle via +ai.skip_generative_ai_when_market_closed+
  # in algo.yml or Settings → AI. Dashboard + POST ai_snapshot honor the same flag;
  # use +force=true+ on the snapshot endpoint to override when authenticated.
  class GenerativeAiMarketGate
    def self.skip?(force: false)
      return false if force
      return false unless flag_enabled?

      TradingSession::Service.market_closed?
    rescue StandardError => e
      Rails.logger.warn("[Ai::GenerativeAiMarketGate] #{e.class} - #{e.message}")
      false
    end

    def self.flag_enabled?
      v = AlgoConfig.fetch.dig(:ai, :skip_generative_ai_when_market_closed)
      ActiveModel::Type::Boolean.new.cast(v)
    rescue StandardError
      false
    end

    # Human-readable context for logs when +skip?+ is true (avoid silent job skips).
    def self.skip_explanation
      closed = TradingSession::Service.market_closed?
      "skip_generative_ai_when_market_closed=#{flag_enabled?}, market_closed=#{closed}"
    rescue StandardError => e
      "gate state unavailable (#{e.class}: #{e.message})"
    end
  end
end
