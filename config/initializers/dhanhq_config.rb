# frozen_string_literal: true

require "dhan_hq"

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
    enabled: true,  # Always enabled - no ENV check needed
    ws_enabled: true,  # Always enabled - no ENV check needed
    order_ws_enabled: true,  # Always enabled - no ENV check needed
    ws_mode: (ENV["DHANHQ_WS_MODE"] || "quote").to_sym,
    ws_watchlist: ENV["DHANHQ_WS_WATCHLIST"],
    order_ws_url: ENV["DHANHQ_WS_ORDER_URL"],
    ws_user_type: ENV["DHANHQ_WS_USER_TYPE"],
    partner_id: ENV["DHANHQ_PARTNER_ID"],
    partner_secret: ENV["DHANHQ_PARTNER_SECRET"]
  )
end
