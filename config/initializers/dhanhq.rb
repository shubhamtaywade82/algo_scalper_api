# frozen_string_literal: true

if defined?(DhanHQ)
  Rails.application.config.x.dhanhq = ActiveSupport::InheritableOptions.new unless Rails.application.config.x.respond_to?(:dhanhq)

  config = Rails.application.config.x.dhanhq
  boolean_type = ActiveModel::Type::Boolean.new

  config.enabled = boolean_type.cast(ENV.fetch("DHANHQ_ENABLED", "false"))
  config.ws_enabled = boolean_type.cast(ENV.fetch("DHANHQ_WS_ENABLED", ENV.fetch("DHANHQ_ENABLED", "false")))
  config.ws_mode = (ENV["DHANHQ_WS_MODE"] || "quote").downcase.to_sym
  config.order_ws_enabled = boolean_type.cast(ENV.fetch("DHANHQ_ORDER_WS_ENABLED", config.ws_enabled))
  config.base_url = ENV.fetch("DHANHQ_BASE_URL", "https://api.dhan.co/v2")
  config.ws_version = Integer(ENV.fetch("DHANHQ_WS_VERSION", 2))

  if config.enabled
    client_id = ENV["DHANHQ_CLIENT_ID"] || ENV["CLIENT_ID"]
    access_token = ENV["DHANHQ_ACCESS_TOKEN"] || ENV["ACCESS_TOKEN"]

    if client_id.blank? || access_token.blank?
      Rails.logger.warn("DhanHQ integration enabled but credentials missing. Set DHANHQ_CLIENT_ID and DHANHQ_ACCESS_TOKEN.")
      config.enabled = false
      config.ws_enabled = false
      config.order_ws_enabled = false
    else
      DhanHQ.configure do |cfg|
        cfg.client_id = client_id
        cfg.access_token = access_token
        cfg.base_url = config.base_url
        cfg.ws_version = config.ws_version
        cfg.ws_order_url = ENV["DHANHQ_WS_ORDER_URL"] if ENV["DHANHQ_WS_ORDER_URL"].present?
        cfg.ws_user_type = ENV["DHANHQ_WS_USER_TYPE"] if ENV["DHANHQ_WS_USER_TYPE"].present?
        cfg.partner_id = ENV["DHANHQ_PARTNER_ID"] if ENV["DHANHQ_PARTNER_ID"].present?
        cfg.partner_secret = ENV["DHANHQ_PARTNER_SECRET"] if ENV["DHANHQ_PARTNER_SECRET"].present?
      end

      log_level_constant = begin
        level = (ENV["DHANHQ_LOG_LEVEL"] || ENV["DHAN_LOG_LEVEL"] || "INFO").upcase
        Logger.const_get(level)
      rescue NameError
        Rails.logger.warn("Unknown DHANHQ_LOG_LEVEL provided. Falling back to INFO.")
        Logger::INFO
      end

      DhanHQ.logger.level = log_level_constant

      Rails.logger.info("DhanHQ integration enabled (base_url=#{config.base_url}, ws_mode=#{config.ws_mode}).")
    end
  else
    Rails.logger.info("DhanHQ integration disabled. Set DHANHQ_ENABLED=true to enable.")
    config.ws_enabled = false
    config.order_ws_enabled = false
  end
else
  Rails.logger.info("DhanHQ gem not available; integration skipped.")
end
