# frozen_string_literal: true

module Entries
  module Guards
    class LtpResolutionGuard
      class << self
        def call(context)
          pick = context[:pick]
          instrument = context[:instrument]
          index_cfg = context[:index_cfg]

          # Log WebSocket status but never block
          hub = Live::MarketFeedHub.instance
          unless hub.running? && hub.connected?
            Rails.logger.info('[EntryGuard] WebSocket not connected - will use REST API fallback for LTP')
          end

          ltp = pick[:ltp]
          ltp = EntryGuard.resolve_entry_ltp(instrument: instrument, pick: pick, index_cfg: index_cfg) if ltp.blank? || EntryGuard.needs_api_ltp?(pick)

          return { blocked: "invalid LTP for #{index_cfg[:key]}: #{pick[:symbol]} (ltp: #{ltp.inspect})" } unless ltp.present? && ltp.to_f.positive?

          context[:ltp] = ltp
          EntryGuardPipeline::PASS
        end
      end
    end
  end
end
