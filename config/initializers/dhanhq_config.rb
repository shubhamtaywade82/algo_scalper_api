# frozen_string_literal: true

require "DhanHQ"

# Bootstrap DhanHQ from ENV only
# expects CLIENT_ID/ACCESS_TOKEN or DHANHQ_CLIENT_ID/DHANHQ_ACCESS_TOKEN
DhanHQ.configure_with_env

level_name = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase
begin
  DhanHQ.logger.level = Logger.const_get(level_name)
rescue NameError
  DhanHQ.logger.level = Logger::INFO
end

# Configure Rails app settings for DhanHQ integration
Rails.application.configure do
  config.x.dhanhq = ActiveSupport::InheritableOptions.new(
    enabled: ENV["DHANHQ_ENABLED"] == "true",
    ws_enabled: ENV["DHANHQ_WS_ENABLED"] == "true",
    order_ws_enabled: ENV["DHANHQ_ORDER_WS_ENABLED"] == "true",
    ws_mode: (ENV["DHANHQ_WS_MODE"] || "quote").to_sym,
    ws_watchlist: ENV["DHANHQ_WS_WATCHLIST"],
    order_ws_url: ENV["DHANHQ_WS_ORDER_URL"],
    ws_user_type: ENV["DHANHQ_WS_USER_TYPE"],
    partner_id: ENV["DHANHQ_PARTNER_ID"],
    partner_secret: ENV["DHANHQ_PARTNER_SECRET"]
  )
end
