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
