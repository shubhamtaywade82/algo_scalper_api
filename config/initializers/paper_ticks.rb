# frozen_string_literal: true

# Hook MarketFeedHub ticks to Paper::Gateway for MTM updates
# Only enabled when PAPER_MODE=true
Rails.application.config.to_prepare do
  next unless ExecutionMode.paper?

  Live::MarketFeedHub.instance.on_tick do |tick|
    segment = tick[:segment] || tick['exchangeSegment']
    security_id = tick[:security_id] || tick['securityId'] || tick['security_id']
    ltp_raw = tick[:ltp] || tick['ltp'] || tick['lastTradedPrice']

    next unless segment && security_id && ltp_raw

    ltp = ltp_raw.to_f
    next if ltp.zero?

    begin
      Orders.config.on_tick(segment: segment.to_s, security_id: security_id.to_s, ltp: ltp)
    rescue StandardError => e
      Rails.logger.error("[PaperTicks] Failed to process tick: #{e.class} - #{e.message}")
    end
  end

  Rails.logger.info('[PaperTicks] Paper mode tick hook registered')
end

