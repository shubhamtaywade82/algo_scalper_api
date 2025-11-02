# frozen_string_literal: true

# WebSocket Market Feed Diagnostics
# Usage: bundle exec rails runner "load 'lib/tasks/ws_feed_diagnostics.rb'"

module WsFeedDiagnostics
  class << self
    def run
      puts "\n" + "=" * 80
      puts "WebSocket Market Feed Diagnostics"
      puts "=" * 80
      puts

      hub = Live::MarketFeedHub.instance
      diagnostics = hub.diagnostics

      # Hub Status
      puts "📊 Hub Status:"
      puts "  Running: #{diagnostics[:hub_status][:running] ? '✅ Yes' : '❌ No'}"
      puts "  Connected: #{diagnostics[:hub_status][:connected] ? '✅ Yes' : '❌ No'}"
      puts "  Connection State: #{diagnostics[:hub_status][:connection_state].to_s.upcase}"
      puts "  Started At: #{diagnostics[:hub_status][:started_at] || 'Not started'}"
      puts "  Last Tick: #{diagnostics[:last_tick]}"
      puts "  Watchlist Size: #{diagnostics[:hub_status][:watchlist_size]}"
      puts

      # Credentials
      puts "🔐 Credentials:"
      puts "  Client ID: #{diagnostics[:credentials][:client_id]}"
      puts "  Access Token: #{diagnostics[:credentials][:access_token]}"
      puts

      # Configuration
      puts "⚙️  Configuration:"
      puts "  Enabled: #{diagnostics[:enabled] ? '✅ Yes' : '❌ No'}"
      puts "  Mode: #{diagnostics[:mode]}"
      puts

      # Last Error
      if diagnostics[:last_error_details]
        puts "❌ Last Error:"
        error = diagnostics[:last_error_details]
        puts "  Error: #{error[:error]}"
        puts "  At: #{error[:at]}"
        puts
      end

      # Feed Health Service
      puts "🏥 Feed Health Service:"
      begin
        health_service = Live::FeedHealthService.instance
        ticks_stale = health_service.stale?(:ticks)
        puts "  Ticks Feed: #{ticks_stale ? '❌ STALE' : '✅ Healthy'}"

        if ticks_stale
          threshold_overrides = health_service.instance_variable_get(:@threshold_overrides) rescue {}
          threshold = threshold_overrides[:ticks] ||
                      Live::FeedHealthService::DEFAULT_THRESHOLDS[:ticks]
          puts "  Threshold: #{threshold} seconds"

          timestamps = health_service.instance_variable_get(:@timestamps) rescue {}
          last_seen = timestamps[:ticks]
          if last_seen
            seconds_ago = (Time.current - last_seen).round(1)
            puts "  Last Success: #{seconds_ago} seconds ago"
          else
            puts "  Last Success: Never"
          end

          failures = health_service.instance_variable_get(:@failures) rescue {}
          failure_info = failures[:ticks]
          if failure_info
            puts "  Last Failure: #{failure_info[:error]}"
            puts "  Failure At: #{failure_info[:at]}"
          end
        end
      rescue StandardError => e
        puts "  ⚠️  Could not check FeedHealthService: #{e.message}"
      end
      puts

      # Recommendations
      puts "💡 Recommendations:"
      recommendations = []

      unless diagnostics[:hub_status][:running]
        recommendations << "  - Start the hub: Live::MarketFeedHub.instance.start!"
      end

      unless diagnostics[:hub_status][:connected]
        if diagnostics[:hub_status][:running]
          recommendations << "  - Hub is running but not connected - check WebSocket connection"
          recommendations << "  - Verify DhanHQ credentials are valid and not expired"
          recommendations << "  - Check network connectivity to DhanHQ servers"
        end
      end

      if diagnostics[:last_tick] == 'Never' && diagnostics[:hub_status][:running]
        recommendations << "  - No ticks received - verify subscriptions and market status"
      end

      if ticks_stale
        recommendations << "  - Ticks feed is stale - investigate connection issues"
      end

      if diagnostics[:last_error_details]
        recommendations << "  - Review last error and check application logs"
      end

      if recommendations.empty?
        puts "  ✅ No issues detected!"
      else
        recommendations.each { |rec| puts rec }
      end

      puts
      puts "=" * 80

      # Return summary
      {
        healthy: diagnostics[:hub_status][:running] &&
                 diagnostics[:hub_status][:connected] &&
                 !ticks_stale,
        diagnostics: diagnostics
      }
    end
  end
end

# Run diagnostics if loaded directly
WsFeedDiagnostics.run if __FILE__ == $PROGRAM_NAME || defined?(Rails::Console)

