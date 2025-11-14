# frozen_string_literal: true
# config/initializers/trading_supervisor.rb

# Only run inside the Rails server (puma) process — prevents vite/webpack/other bin/dev processes from executing this file
return unless defined?(Rails::Server)
return if Rails.env.test?
return if Rails.const_defined?(:Console)

Rails.application.config.after_initialize do
  # Force load the classes so initializer won't fail due to Zeitwerk ordering
  # (adjust paths if you moved files)
  require_dependency Rails.root.join('app/services/live/market_feed_hub').to_s
  require_dependency Rails.root.join('app/services/tick_cache').to_s
  require_dependency Rails.root.join('app/services/live/redis_tick_cache').to_s

  logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)

  begin
    # start the singleton MarketFeedHub (your current implementation uses Singleton)
    # It will load watchlist internally and call subscribe_watchlist
    started = Live::MarketFeedHub.instance.start!
    logger.info("[trading_supervisor] MarketFeedHub.start! => #{started.inspect}")

    # quick sanity: make sure TickCache is present
    if defined?(Live::TickCache)
      logger.info("[trading_supervisor] Live::TickCache ready")
    else
      logger.warn("[trading_supervisor] Live::TickCache NOT loaded")
    end
  rescue Exception => e
    logger.error("[trading_supervisor] failed to start MarketFeedHub: #{e.class} - #{e.message}\n#{e.backtrace.first(10).join("\n")}")
  end
end
