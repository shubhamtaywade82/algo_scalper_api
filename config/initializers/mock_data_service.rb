# Start mock data service if WebSocket is disabled
Rails.application.config.after_initialize do
  if Rails.env.development? && !Rails.env.test? && ENV["DHANHQ_WS_ENABLED"] == "false"
    # Rails.logger.info("[MockData] Starting mock data service (WebSocket disabled)")
    Live::MockDataService.instance.start!
  end
end
