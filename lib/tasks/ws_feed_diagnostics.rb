# frozen_string_literal: true

# WebSocket Market Feed Diagnostics
# Usage: bundle exec rails runner "load 'lib/tasks/ws_feed_diagnostics.rb'"

module WsFeedDiagnostics
  class << self
    def run
      Rails.logger.debug { "\n#{'=' * 80}" }
      Rails.logger.debug 'WebSocket Market Feed Diagnostics'
      Rails.logger.debug '=' * 80
      Rails.logger.debug

      hub = Live::MarketFeedHub.instance
      diagnostics = hub.diagnostics

      # Hub Status
      Rails.logger.debug '📊 Hub Status:'
      Rails.logger.debug { "  Running: #{diagnostics[:hub_status][:running] ? '✅ Yes' : '❌ No'}" }
      Rails.logger.debug { "  Connected: #{diagnostics[:hub_status][:connected] ? '✅ Yes' : '❌ No'}" }
      Rails.logger.debug { "  Connection State: #{diagnostics[:hub_status][:connection_state].to_s.upcase}" }
      Rails.logger.debug { "  Started At: #{diagnostics[:hub_status][:started_at] || 'Not started'}" }
      Rails.logger.debug { "  Last Tick: #{diagnostics[:last_tick]}" }
      Rails.logger.debug { "  Watchlist Size: #{diagnostics[:hub_status][:watchlist_size]}" }
      Rails.logger.debug

      # Credentials
      Rails.logger.debug '🔐 Credentials:'
      Rails.logger.debug { "  Client ID: #{diagnostics[:credentials][:client_id]}" }
      Rails.logger.debug { "  Access Token: #{diagnostics[:credentials][:access_token]}" }
      Rails.logger.debug

      # Configuration
      Rails.logger.debug '⚙️  Configuration:'
      Rails.logger.debug { "  Enabled: #{diagnostics[:enabled] ? '✅ Yes' : '❌ No'}" }
      Rails.logger.debug { "  Mode: #{diagnostics[:mode]}" }
      Rails.logger.debug

      # Last Error
      if diagnostics[:last_error_details]
        Rails.logger.debug '❌ Last Error:'
        error = diagnostics[:last_error_details]
        Rails.logger.debug { "  Error: #{error[:error]}" }
        Rails.logger.debug { "  At: #{error[:at]}" }
        Rails.logger.debug
      end

      # Feed Health Service
      Rails.logger.debug '🏥 Feed Health Service:'
      begin
        health_service = Live::FeedHealthService.instance
        ticks_stale = health_service.stale?(:ticks)
        Rails.logger.debug { "  Ticks Feed: #{ticks_stale ? '❌ STALE' : '✅ Healthy'}" }

        if ticks_stale
          threshold_overrides = begin
            health_service.instance_variable_get(:@threshold_overrides)
          rescue StandardError
            {}
          end
          threshold = threshold_overrides[:ticks] ||
                      Live::FeedHealthService::DEFAULT_THRESHOLDS[:ticks]
          Rails.logger.debug { "  Threshold: #{threshold} seconds" }

          timestamps = begin
            health_service.instance_variable_get(:@timestamps)
          rescue StandardError
            {}
          end
          last_seen = timestamps[:ticks]
          if last_seen
            seconds_ago = (Time.current - last_seen).round(1)
            Rails.logger.debug { "  Last Success: #{seconds_ago} seconds ago" }
          else
            Rails.logger.debug '  Last Success: Never'
          end

          failures = begin
            health_service.instance_variable_get(:@failures)
          rescue StandardError
            {}
          end
          failure_info = failures[:ticks]
          if failure_info
            Rails.logger.debug { "  Last Failure: #{failure_info[:error]}" }
            Rails.logger.debug { "  Failure At: #{failure_info[:at]}" }
          end
        end
      rescue StandardError => e
        Rails.logger.debug { "  ⚠️  Could not check FeedHealthService: #{e.message}" }
      end
      Rails.logger.debug

      # Recommendations
      Rails.logger.debug '💡 Recommendations:'
      recommendations = []

      unless diagnostics[:hub_status][:running]
        recommendations << '  - Start the hub: Live::MarketFeedHub.instance.start!'
      end

      if !diagnostics[:hub_status][:connected] && diagnostics[:hub_status][:running]
        recommendations << '  - Hub is running but not connected - check WebSocket connection'
        recommendations << '  - Verify DhanHQ credentials are valid and not expired'
        recommendations << '  - Check network connectivity to DhanHQ servers'
      end

      if diagnostics[:last_tick] == 'Never' && diagnostics[:hub_status][:running]
        recommendations << '  - No ticks received - verify subscriptions and market status'
      end

      recommendations << '  - Ticks feed is stale - investigate connection issues' if ticks_stale

      recommendations << '  - Review last error and check application logs' if diagnostics[:last_error_details]

      if recommendations.empty?
        Rails.logger.debug '  ✅ No issues detected!'
      else
        recommendations.each { |rec| Rails.logger.debug rec }
      end

      Rails.logger.debug
      Rails.logger.debug '=' * 80

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
