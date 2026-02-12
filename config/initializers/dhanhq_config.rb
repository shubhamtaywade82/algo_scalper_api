# frozen_string_literal: true

require "dhan_hq"

# Ensure error constants are loaded before `DhanHQ::Constants` references them.
require "DhanHQ/errors"

# Normalize environment variables to support both naming conventions
# The DhanHQ gem expects variables with DHAN_ prefix (or CLIENT_ID/ACCESS_TOKEN)
# We support both DHANHQ_ and DHAN_ prefixes for flexibility

# Required credentials - support both naming conventions
ENV['CLIENT_ID'] ||= ENV['DHAN_CLIENT_ID'] if ENV['DHAN_CLIENT_ID'].present?
ENV['ACCESS_TOKEN'] ||= ENV['DHAN_ACCESS_TOKEN'] if ENV['DHAN_ACCESS_TOKEN'].present?

# Optional gem configuration - normalize DHANHQ_ prefix to DHAN_ prefix for gem compatibility
# The gem's configure_with_env reads directly from ENV with DHAN_ prefix
ENV['DHAN_BASE_URL'] ||= ENV['DHANHQ_BASE_URL'] if ENV['DHANHQ_BASE_URL'].present?
ENV['DHAN_WS_VERSION'] ||= ENV['DHANHQ_WS_VERSION'] if ENV['DHANHQ_WS_VERSION'].present?
ENV['DHAN_WS_ORDER_URL'] ||= ENV['DHANHQ_WS_ORDER_URL'] if ENV['DHANHQ_WS_ORDER_URL'].present?
ENV['DHAN_WS_MARKET_FEED_URL'] ||= ENV['DHANHQ_WS_MARKET_FEED_URL'] if ENV['DHANHQ_WS_MARKET_FEED_URL'].present?
ENV['DHAN_WS_MARKET_DEPTH_URL'] ||= ENV['DHANHQ_WS_MARKET_DEPTH_URL'] if ENV['DHANHQ_WS_MARKET_DEPTH_URL'].present?
ENV['DHAN_MARKET_DEPTH_LEVEL'] ||= ENV['DHANHQ_MARKET_DEPTH_LEVEL'] if ENV['DHANHQ_MARKET_DEPTH_LEVEL'].present?
ENV['DHAN_WS_USER_TYPE'] ||= ENV['DHANHQ_WS_USER_TYPE'] if ENV['DHANHQ_WS_USER_TYPE'].present?
ENV['DHAN_PARTNER_ID'] ||= ENV['DHANHQ_PARTNER_ID'] if ENV['DHANHQ_PARTNER_ID'].present?
ENV['DHAN_PARTNER_SECRET'] ||= ENV['DHANHQ_PARTNER_SECRET'] if ENV['DHANHQ_PARTNER_SECRET'].present?
ENV['DHAN_LOG_LEVEL'] ||= ENV['DHANHQ_LOG_LEVEL'] if ENV['DHANHQ_LOG_LEVEL'].present?

# Bootstrap DhanHQ from ENV only
# The gem reads: CLIENT_ID, ACCESS_TOKEN, and all DHAN_* variables
DhanHQ.configure_with_env

# Set logger level (supports both DHAN_LOG_LEVEL and DHANHQ_LOG_LEVEL via normalization above)
level_name = (ENV["DHAN_LOG_LEVEL"] || "INFO").upcase
begin
  DhanHQ.logger.level = Logger.const_get(level_name)
rescue NameError
  DhanHQ.logger.level = Logger::INFO
end

# Configure Rails app settings for DhanHQ integration
# Disable WebSocket in test, backtest, or script mode
skip_ws = Rails.env.test? ||
          ENV['BACKTEST_MODE'] == '1' ||
          ENV['SCRIPT_MODE'] == '1' ||
          ENV['DISABLE_TRADING_SERVICES'] == '1' ||
          ($PROGRAM_NAME.include?('runner') if defined?($PROGRAM_NAME))

Rails.application.configure do
  config.x.dhanhq = ActiveSupport::InheritableOptions.new(
    enabled: !Rails.env.test? && !skip_ws,  # Disable in test environment or script mode
    ws_enabled: !skip_ws,  # Disable WebSocket in test environment or script mode
    order_ws_enabled: !skip_ws,  # Disable order WebSocket in test environment or script mode
    enable_order_logging: ENV["ENABLE_ORDER"] == "true",  # Order payload logging
    ws_mode: (ENV["DHANHQ_WS_MODE"] || "quote").to_sym,
    ws_watchlist: ENV["DHANHQ_WS_WATCHLIST"],
    order_ws_url: ENV["DHANHQ_WS_ORDER_URL"],
    ws_user_type: ENV["DHANHQ_WS_USER_TYPE"],
    partner_id: ENV["DHANHQ_PARTNER_ID"],
    partner_secret: ENV["DHANHQ_PARTNER_SECRET"]
  )
end

# Prefer DHAN_CLIENT_ID; fall back to CLIENT_ID for compatibility.
client_id = ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
DhanHQ.configuration.client_id = client_id if client_id

# Inject access token from DB so the gem always uses the latest valid token.
# No refresh API exists; token must be renewed via /auth/dhan/login when expired.
DhanHQ.configuration.define_singleton_method(:access_token) do
  record = DhanAccessToken.active
  record ? record.token : instance_variable_get(:@token)
end