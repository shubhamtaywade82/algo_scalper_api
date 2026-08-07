Failures:

  1) Config pinning on exit path adaptive trail hard stop uses pinned config snapshot fires at pinned -20% hard stop rather than live -99%
     Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
       #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
     # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
     # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
     # ./app/services/risk/rules/rule_engine.rb:39:in `each'
     # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
     # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
     # ./spec/integration/config_pinning_exit_spec.rb:50:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
     # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  2) Database Persistence Integration Position Tracker Persistence when managing metadata handles breakeven lock status
     Failure/Error: expect(position_tracker.breakeven_locked?).to be true

       expected true
            got false
     # ./spec/integration/database_persistence_spec.rb:200:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  3) Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker subscribes to market feed subscribes to underlying instrument for options
     Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "225")
     # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
     # ./app/services/positions/index_sync.rb:15:in `register'
     # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
     # ./spec/integration/dynamic_subscription_spec.rb:99:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  4) Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker subscribes to market feed handles subscription errors gracefully
     Failure/Error: Rails.logger.error("[Positions::FeedSubscription] #{e.class} - #{e.message}")

       #<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast"> received :error with unexpected arguments
         expected: (/Failed to subscribe/)
              got: ("[Positions::FeedSubscription] StandardError - Subscription error")
       Diff:
       @@ -1 +1 @@
       -[/Failed to subscribe/]
       +["[Positions::FeedSubscription] StandardError - Subscription error"]

     # ./app/services/positions/feed_subscription.rb:47:in `rescue in subscribe'
     # ./app/services/positions/feed_subscription.rb:39:in `subscribe'
     # ./app/services/positions/feed_subscription.rb:10:in `call'
     # ./app/services/application_service.rb:5:in `call'
     # ./app/models/concerns/position_tracker/indexable.rb:15:in `subscribe'
     # ./spec/integration/dynamic_subscription_spec.rb:110:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
     # ------------------
     # --- Caused by: ---
     # StandardError:
     #   Subscription error
     #   ./app/services/positions/feed_subscription.rb:45:in `subscribe'

  5) Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker unsubscribes from market feed unsubscribes from underlying instrument for options
     Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "228")
     # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
     # ./app/services/positions/index_sync.rb:15:in `register'
     # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
     # ./spec/integration/dynamic_subscription_spec.rb:144:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  6) Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker unsubscribes from market feed handles missing segment gracefully
     Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "229")
     # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
     # ./app/services/positions/index_sync.rb:15:in `register'
     # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
     # ./spec/integration/dynamic_subscription_spec.rb:162:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  7) Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes subscribes when position becomes active
     Failure/Error: redis.srem(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :srem with ("positions:active_tracker_ids", "231")
     # ./app/services/positions/index_sync.rb:95:in `remove_active_tracker_id'
     # ./app/services/positions/index_sync.rb:24:in `unregister'
     # ./app/services/positions/index_sync.rb:32:in `refresh_if_relevant'
     # ./app/models/concerns/position_tracker/indexable.rb:39:in `refresh_index_if_relevant'
     # ./spec/integration/dynamic_subscription_spec.rb:181:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  8) Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes unsubscribes when position is exited
     Failure/Error: redis.srem(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :srem with ("positions:active_tracker_ids", "232")
     # ./app/services/positions/index_sync.rb:95:in `remove_active_tracker_id'
     # ./app/services/positions/index_sync.rb:24:in `unregister'
     # ./app/services/positions/index_sync.rb:32:in `refresh_if_relevant'
     # ./app/models/concerns/position_tracker/indexable.rb:39:in `refresh_index_if_relevant'
     # ./app/services/positions/exit_flow.rb:17:in `call'
     # ./app/services/application_service.rb:5:in `call'
     # ./app/models/concerns/position_tracker/lifecycle.rb:48:in `mark_exited!'
     # ./spec/integration/dynamic_subscription_spec.rb:197:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  9) Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes does not subscribe when position is cancelled
     Failure/Error: redis.srem(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
       #<Double "Redis"> received unexpected message :srem with ("positions:active_tracker_ids", "233")
     # ./app/services/positions/index_sync.rb:95:in `remove_active_tracker_id'
     # ./app/services/positions/index_sync.rb:24:in `unregister'
     # ./app/services/positions/index_sync.rb:32:in `refresh_if_relevant'
     # ./app/models/concerns/position_tracker/indexable.rb:39:in `refresh_index_if_relevant'
     # ./app/models/concerns/position_tracker/lifecycle.rb:44:in `mark_cancelled!'
     # ./spec/integration/dynamic_subscription_spec.rb:203:in `block (4 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
     # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
     # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
     # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  10) Dynamic Subscription Integration Watchlist-based Dynamic Subscription when loading watchlist from database handles empty environment variable
      Failure/Error: expect(watchlist).to eq([])

        expected: []
             got: [{:security_id=>"21", :segment=>"IDX_I"}]

        (compared using ==)

        Diff:
        @@ -1 +1 @@
        -[]
        +[{:security_id=>"21", :segment=>"IDX_I"}]

      # ./spec/integration/dynamic_subscription_spec.rb:237:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  11) Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions syncs positions from DhanHQ to database
      Failure/Error: redis_client.smembers(ACTIVE_TRACKER_SET_KEY).to_set
        #<Double "Redis"> received unexpected message :smembers with ("positions:active_tracker_ids")
      # ./app/services/positions/index_sync.rb:65:in `active_tracker_ids_from_redis'
      # ./app/services/positions/index_sync.rb:40:in `clear_orphaned_redis_pnl!'
      # ./app/models/concerns/position_tracker/queryable.rb:84:in `clear_orphaned_redis_pnl!'
      # ./app/services/live/position_sync_service.rb:32:in `sync_positions!'
      # ./spec/integration/dynamic_subscription_spec.rb:385:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  12) Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions creates trackers for untracked positions
      Failure/Error: redis_client.smembers(ACTIVE_TRACKER_SET_KEY).to_set
        #<Double "Redis"> received unexpected message :smembers with ("positions:active_tracker_ids")
      # ./app/services/positions/index_sync.rb:65:in `active_tracker_ids_from_redis'
      # ./app/services/positions/index_sync.rb:40:in `clear_orphaned_redis_pnl!'
      # ./app/models/concerns/position_tracker/queryable.rb:84:in `clear_orphaned_redis_pnl!'
      # ./app/services/live/position_sync_service.rb:32:in `sync_positions!'
      # ./spec/integration/dynamic_subscription_spec.rb:393:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  13) Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions marks orphaned trackers as exited
      Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
        #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "245")
      # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
      # ./app/services/positions/index_sync.rb:15:in `register'
      # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
      # ./spec/integration/dynamic_subscription_spec.rb:407:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  14) Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions handles sync errors gracefully
      Failure/Error: redis_client.smembers(ACTIVE_TRACKER_SET_KEY).to_set
        #<Double "Redis"> received unexpected message :smembers with ("positions:active_tracker_ids")
      # ./app/services/positions/index_sync.rb:65:in `active_tracker_ids_from_redis'
      # ./app/services/positions/index_sync.rb:40:in `clear_orphaned_redis_pnl!'
      # ./app/models/concerns/position_tracker/queryable.rb:84:in `clear_orphaned_redis_pnl!'
      # ./app/services/live/position_sync_service.rb:32:in `sync_positions!'
      # ./spec/integration/dynamic_subscription_spec.rb:425:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  15) Dynamic Subscription Integration Dynamic Subscription Management when managing subscription lifecycle handles hub startup errors gracefully
      Failure/Error: expect(Rails.logger).to receive(:error).with(/Failed to start DhanHQ market feed/)

        (#<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast">).error(/Failed to start DhanHQ market feed/)
            expected: 1 time with arguments: (/Failed to start DhanHQ market feed/)
            received: 2 times with arguments: (/Failed to start DhanHQ market feed/)
      # ./spec/integration/dynamic_subscription_spec.rb:532:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  16) Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles WebSocket connection errors
      Failure/Error: Rails.logger.error("[Positions::FeedSubscription] #{e.class} - #{e.message}")

        #<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast"> received :error with unexpected arguments
          expected: (/Failed to subscribe/)
               got: ("[Positions::FeedSubscription] StandardError - WebSocket error")
        Diff:
        @@ -1 +1 @@
        -[/Failed to subscribe/]
        +["[Positions::FeedSubscription] StandardError - WebSocket error"]

      # ./app/services/positions/feed_subscription.rb:47:in `rescue in subscribe'
      # ./app/services/positions/feed_subscription.rb:39:in `subscribe'
      # ./app/services/positions/feed_subscription.rb:10:in `call'
      # ./app/services/application_service.rb:5:in `call'
      # ./app/models/concerns/position_tracker/indexable.rb:15:in `subscribe'
      # ./spec/integration/dynamic_subscription_spec.rb:597:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ------------------
      # --- Caused by: ---
      # StandardError:
      #   WebSocket error
      #   ./app/services/positions/feed_subscription.rb:45:in `subscribe'

  17) Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles missing security ID errors
      Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
        #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "259")
      # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
      # ./app/services/positions/index_sync.rb:15:in `register'
      # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
      # ./spec/integration/dynamic_subscription_spec.rb:616:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  18) Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles subscription timeout errors
      Failure/Error: Rails.logger.error("[Positions::FeedSubscription] #{e.class} - #{e.message}")

        #<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast"> received :error with unexpected arguments
          expected: (/Failed to subscribe/)
               got: ("[Positions::FeedSubscription] Timeout::Error - Subscription timeout")
        Diff:
        @@ -1 +1 @@
        -[/Failed to subscribe/]
        +["[Positions::FeedSubscription] Timeout::Error - Subscription timeout"]

      # ./app/services/positions/feed_subscription.rb:47:in `rescue in subscribe'
      # ./app/services/positions/feed_subscription.rb:39:in `subscribe'
      # ./app/services/positions/feed_subscription.rb:10:in `call'
      # ./app/services/application_service.rb:5:in `call'
      # ./app/models/concerns/position_tracker/indexable.rb:15:in `subscribe'
      # ./spec/integration/dynamic_subscription_spec.rb:631:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ------------------
      # --- Caused by: ---
      # Timeout::Error:
      #   Subscription timeout
      #   ./app/services/positions/feed_subscription.rb:45:in `subscribe'

  19) Dynamic Subscription Integration Subscription Error Handling when handling unsubscription errors handles WebSocket disconnection errors
      Failure/Error: expect { position_tracker.unsubscribe }.to raise_error(StandardError, 'WebSocket error')
        expected StandardError with "WebSocket error" but nothing was raised
      # ./spec/integration/dynamic_subscription_spec.rb:641:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  20) Dynamic Subscription Integration Performance and Scalability when handling large numbers of subscriptions efficiently manages multiple subscriptions
      Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
        #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "264")
      # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
      # ./app/services/positions/index_sync.rb:15:in `register'
      # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/evaluation.rb:15:in `create'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy/create.rb:14:in `block in result'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy/create.rb:11:in `result'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory.rb:48:in `run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory_runner.rb:29:in `block in run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory_runner.rb:28:in `run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy_syntax_method_registrar.rb:28:in `block in define_singular_strategy_method'
      # ./spec/integration/dynamic_subscription_spec.rb:661:in `block (5 levels) in <top (required)>'
      # ./spec/integration/dynamic_subscription_spec.rb:660:in `initialize'
      # ./spec/integration/dynamic_subscription_spec.rb:660:in `new'
      # ./spec/integration/dynamic_subscription_spec.rb:660:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  21) Dynamic Subscription Integration Performance and Scalability when handling large numbers of subscriptions efficiently manages multiple unsubscriptions
      Failure/Error: redis.sadd(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
        #<Double "Redis"> received unexpected message :sadd with ("positions:active_tracker_ids", "266")
      # ./app/services/positions/index_sync.rb:88:in `add_active_tracker_id'
      # ./app/services/positions/index_sync.rb:15:in `register'
      # ./app/models/concerns/position_tracker/indexable.rb:25:in `register_in_index'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/evaluation.rb:15:in `create'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy/create.rb:14:in `block in result'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy/create.rb:11:in `result'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory.rb:48:in `run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory_runner.rb:29:in `block in run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/factory_runner.rb:28:in `run'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/factory_bot-6.5.6/lib/factory_bot/strategy_syntax_method_registrar.rb:28:in `block in define_singular_strategy_method'
      # ./spec/integration/dynamic_subscription_spec.rb:677:in `block (5 levels) in <top (required)>'
      # ./spec/integration/dynamic_subscription_spec.rb:676:in `initialize'
      # ./spec/integration/dynamic_subscription_spec.rb:676:in `new'
      # ./spec/integration/dynamic_subscription_spec.rb:676:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  22) Dynamic Subscription Integration Integration with Trading System when integrating with exit system unsubscribes from instruments when exiting positions
      Failure/Error: redis.srem(ACTIVE_TRACKER_SET_KEY, tracker.id.to_s)
        #<Double "Redis"> received unexpected message :srem with ("positions:active_tracker_ids", "272")
      # ./app/services/positions/index_sync.rb:95:in `remove_active_tracker_id'
      # ./app/services/positions/index_sync.rb:24:in `unregister'
      # ./app/services/positions/index_sync.rb:32:in `refresh_if_relevant'
      # ./app/models/concerns/position_tracker/indexable.rb:39:in `refresh_index_if_relevant'
      # ./app/services/positions/exit_flow.rb:17:in `call'
      # ./app/services/application_service.rb:5:in `call'
      # ./app/models/concerns/position_tracker/lifecycle.rb:48:in `mark_exited!'
      # ./spec/integration/dynamic_subscription_spec.rb:776:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  23) Exit Rules Integration Breakeven Lock Logic when checking breakeven lock status correctly identifies locked breakeven
      Failure/Error: expect(position_tracker.breakeven_locked?).to be true

        expected true
             got false
      # ./spec/integration/exit_rules_spec.rb:286:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  24) Modular Indicator System Integration end-to-end indicator workflow builds indicators via factory and generates signals
      Failure/Error: indicators = Indicators::IndicatorFactory.build_indicators(series: series, config: config)

      NameError:
        uninitialized constant Indicators::IndicatorFactory
      # ./spec/integration/modular_indicator_system_integration_spec.rb:47:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  25) Modular Indicator System Integration end-to-end indicator workflow combines indicators via MultiIndicatorStrategy
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 18 } }
          ],
          confirmation_mode: :all,
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:62:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  26) Modular Indicator System Integration all indicator types integration works with all available indicators
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 18 } },
            { type: 'rsi', config: { period: 14 } },
            { type: 'macd', config: { fast_period: 12, slow_period: 26, signal_period: 9 } },
            { type: 'trend_duration', config: { hma_length: 20, trend_length: 5 } }
          ],
          confirmation_mode: :majority,

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:85:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  27) Modular Indicator System Integration confirmation modes integration works with all confirmation mode
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: indicators_config,
          confirmation_mode: :all,
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:116:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  28) Modular Indicator System Integration confirmation modes integration works with majority confirmation mode
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: indicators_config,
          confirmation_mode: :majority,
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:129:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  29) Modular Indicator System Integration confirmation modes integration works with weighted confirmation mode
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: indicators_config,
          confirmation_mode: :weighted,
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:142:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  30) Modular Indicator System Integration confirmation modes integration works with any confirmation mode
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: indicators_config,
          confirmation_mode: :any,
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:155:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  31) Modular Indicator System Integration backward compatibility SupertrendAdxStrategy uses MultiIndicatorStrategy internally
      Failure/Error:
        strategy = SupertrendAdxStrategy.new(
          series: series,
          supertrend_cfg: supertrend_cfg,
          adx_min_strength: 20
        )

      NameError:
        uninitialized constant SupertrendAdxStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:171:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  32) Modular Indicator System Integration configuration-driven workflow builds strategy from configuration
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: enabled_indicators,
          confirmation_mode: signals_cfg[:confirmation_mode],
          min_confidence: signals_cfg[:min_confidence],
          **global_config
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:214:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  33) Modular Indicator System Integration configuration-driven workflow filters out disabled indicators
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: enabled_indicators,
          confirmation_mode: :all
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:238:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  34) Modular Indicator System Integration error handling and resilience handles indicator calculation failures gracefully
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14, min_strength: 18 } }
          ],
          confirmation_mode: :any, # Any can still work if one fails
          min_confidence: 50
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:251:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  35) Modular Indicator System Integration error handling and resilience handles missing indicator configurations
      Failure/Error: indicators = Indicators::IndicatorFactory.build_indicators(series: series, config: config)

      NameError:
        uninitialized constant Indicators::IndicatorFactory
      # ./spec/integration/modular_indicator_system_integration_spec.rb:281:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  36) Modular Indicator System Integration performance with multiple indicators calculates all indicators efficiently
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
            { type: 'adx', config: { period: 14 } },
            { type: 'rsi', config: { period: 14 } },
            { type: 'macd', config: { fast_period: 12, slow_period: 26, signal_period: 9 } }
          ],
          confirmation_mode: :all
        )

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/modular_indicator_system_integration_spec.rb:289:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  37) OHLC Data Fetch Integration Instrument OHLC Data Fetching when fetching current OHLC data fetches current OHLC from market feed
      Failure/Error: expect(result).to eq(mock_ohlc_response.dig('data', 'NSE_FNO', '12345'))

        expected: {"close"=>101.2, "high"=>101.5, "low"=>99.8, "open"=>100.0, "volume"=>10000}
             got: nil

        (compared using ==)
      # ./spec/integration/ohlc_data_fetch_spec.rb:122:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  38) OHLC Data Fetch Integration Instrument OHLC Data Fetching when fetching current OHLC data returns nil when market feed fails
      Failure/Error: Rails.logger.error("[DHAN] Token refresh failed (mode=#{ENV.fetch('DHAN_AUTH_MODE', 'totp')}): #{e.class} - #{e.message}")

        #<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast"> received :error with unexpected arguments
          expected: (/DhanHQ error/)
               got: ("[DHAN] Token refresh failed (mode=totp): VCR::Errors::UnhandledHTTPRequestError - \n\n==============...uest_matching\n================================================================================\n\n")
        Diff:
        @@ -1 +1 @@
        -[/DhanHQ error/]
        +["[DHAN] Token refresh failed (mode=totp): VCR::Errors::UnhandledHTTPRequestError - \n\n================================================================================\nAn HTTP request has been made that VCR does not know how to handle:\n  POST https://auth.dhan.co/app/generateAccessToken?dhanClientId=1104216308&pin=855179&totp=268605\n  Body: \n\nVCR is currently using the following cassette:\n  - /home/nemesis/project/trading-workspace/algo_scalper_api/spec/cassettes/OHLC_Data_Fetch_Integration/Instrument_OHLC_Data_Fetching/when_fetching_current_OHLC_data/returns_nil_when_market_feed_fails.yml\n    - :record => :once\n    - :match_requests_on => [:method, :uri, :body]\n\nUnder the current configuration VCR can not find a suitable HTTP interaction\nto replay and is prevented from recording new requests. There are a few ways\nyou can deal with this:\n\n  * If you're surprised VCR is raising this error\n    and want insight about how VCR attempted to handle the request,\n    you can use the debug_logger configuration option to log more details [1].\n  * You can use the :new_episodes record mode to allow VCR to\n    record this new request to the existing cassette [2].\n  * If you want VCR to ignore this request (and others like it), you can\n    set an `ignore_request` callback [3].\n  * The current record mode (:once) does not allow new requests to be recorded\n    to a previously recorded cassette. You can delete the cassette file and re-run\n    your tests to allow the cassette to be recorded with this request [4].\n  * The cassette contains 1 HTTP interaction that has not been\n    played back. If your request is non-deterministic, you may need to\n    change your :match_requests_on cassette option to be more lenient\n    or use a custom request matcher to allow it to match [5].\n\n[1] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/debug_logging\n[2] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/new_episodes\n[3] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/ignore_request\n[4] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/once\n[5] https://benoittgt.github.io/vcr/?v=6-4-0#/request_matching\n================================================================================\n\n"]

      # ./app/services/dhan/token_manager.rb:60:in `rescue in refresh!'
      # ./app/services/dhan/token_manager.rb:41:in `refresh!'
      # ./app/services/dhan/token_manager.rb:27:in `current_token!'
      # ./config/initializers/dhanhq_config.rb:116:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/configuration.rb:103:in `resolved_access_token'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/helpers/request_helper.rb:56:in `resolved_access_token'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/helpers/request_helper.rb:33:in `build_headers'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:70:in `block (3 levels) in request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/connection.rb:513:in `block in run_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/connection.rb:530:in `block in build_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/request.rb:56:in `block in create'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/request.rb:55:in `create'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/connection.rb:526:in `build_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/connection.rb:508:in `run_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/faraday-1.10.5/lib/faraday/connection.rb:283:in `post'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:69:in `block (2 levels) in request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:93:in `with_transient_retry'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:68:in `block in request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:79:in `with_auth_retry'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:67:in `request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/client.rb:136:in `post'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/core/base_api.rb:42:in `post'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/resources/market_feed.rb:33:in `ohlc'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/DhanHQ-2.8.0/lib/DhanHQ/models/market_feed.rb:140:in `ohlc'
      # ./app/models/concerns/instrument_helpers.rb:273:in `ohlc'
      # ./spec/integration/ohlc_data_fetch_spec.rb:133:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ------------------
      # --- Caused by: ---
      # VCR::Errors::UnhandledHTTPRequestError:
      #
      #
      #   ================================================================================
      #   An HTTP request has been made that VCR does not know how to handle:
      #     POST https://auth.dhan.co/app/generateAccessToken?dhanClientId=1104216308&pin=855179&totp=268605
      #     Body:
      #
      #   VCR is currently using the following cassette:
      #     - /home/nemesis/project/trading-workspace/algo_scalper_api/spec/cassettes/OHLC_Data_Fetch_Integration/Instrument_OHLC_Data_Fetching/when_fetching_current_OHLC_data/returns_nil_when_market_feed_fails.yml
      #       - :record => :once
      #       - :match_requests_on => [:method, :uri, :body]
      #
      #   Under the current configuration VCR can not find a suitable HTTP interaction
      #   to replay and is prevented from recording new requests. There are a few ways
      #   you can deal with this:
      #
      #     * If you're surprised VCR is raising this error
      #       and want insight about how VCR attempted to handle the request,
      #       you can use the debug_logger configuration option to log more details [1].
      #     * You can use the :new_episodes record mode to allow VCR to
      #       record this new request to the existing cassette [2].
      #     * If you want VCR to ignore this request (and others like it), you can
      #       set an `ignore_request` callback [3].
      #     * The current record mode (:once) does not allow new requests to be recorded
      #       to a previously recorded cassette. You can delete the cassette file and re-run
      #       your tests to allow the cassette to be recorded with this request [4].
      #     * The cassette contains 1 HTTP interaction that has not been
      #       played back. If your request is non-deterministic, you may need to
      #       change your :match_requests_on cassette option to be more lenient
      #       or use a custom request matcher to allow it to match [5].
      #
      #   [1] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/debug_logging
      #   [2] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/new_episodes
      #   [3] https://benoittgt.github.io/vcr/?v=6-4-0#/configuration/ignore_request
      #   [4] https://benoittgt.github.io/vcr/?v=6-4-0#/record_modes/once
      #   [5] https://benoittgt.github.io/vcr/?v=6-4-0#/request_matching
      #   ================================================================================
      #   /home/nemesis/.rvm/gems/ruby-3.3.4/gems/vcr-6.4.0/lib/vcr/request_handler.rb:97:in `on_unhandled_request'

  39) Order Placement Integration Order Placer Integration when handling order placement errors handles API errors gracefully
      Failure/Error: DhanHQ::Models::Order.create(payload)

      StandardError:
        API Error
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:172:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  40) Order Placement Integration Order Placer Integration when handling order placement errors handles network timeout errors
      Failure/Error: DhanHQ::Models::Order.create(payload)

      Timeout::Error:
        Request timeout
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:188:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  41) Order Placement Integration Order Placer Integration when handling order placement errors handles invalid order parameters
      Failure/Error: DhanHQ::Models::Order.create(payload)

      ArgumentError:
        Invalid parameters
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:204:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  42) Order Placement Integration Entry Guard Integration when attempting entry calculates correct quantity using capital allocator
      Failure/Error:
        expect(Capital::Allocator).to receive(:qty_for).with(
          index_cfg: index_config,
          entry_price: 100.0,
          derivative_lot_size: expected_lot_size,
          scale_multiplier: 1
        ).and_return(65)

        (Capital::Allocator (class)).qty_for({:derivative_lot_size=>65, :entry_price=>100.0, :index_cfg=>{:key=>"nifty", :max_same_side=>2, :segment=>"NSE_FNO"}, :scale_multiplier=>1})
            expected: 1 time with arguments: ({:derivative_lot_size=>65, :entry_price=>100.0, :index_cfg=>{:key=>"nifty", :max_same_side=>2, :segment=>"NSE_FNO"}, :scale_multiplier=>1})
            received: 0 times
      # ./spec/integration/order_placement_spec.rb:328:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  43) Order Placement Integration Entry Guard Integration when creating position trackers handles tracker creation errors gracefully
      Failure/Error: expect(Rails.logger).to receive(:error).with(/EntryGuard failed for nifty: ActiveRecord::RecordInvalid/)

        (#<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast">).error(/EntryGuard failed for nifty: ActiveRecord::RecordInvalid/)
            expected: 1 time with arguments: (/EntryGuard failed for nifty: ActiveRecord::RecordInvalid/)
            received: 0 times
      # ./spec/integration/order_placement_spec.rb:475:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  44) Order Placement Integration Error Handling and Resilience when handling order placement failures handles broker rejections gracefully
      Failure/Error: DhanHQ::Models::Order.create(payload)

      DhanHQ::Error:
        Order rejected: Insufficient funds
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:664:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  45) Order Placement Integration Error Handling and Resilience when handling order placement failures handles market closure gracefully
      Failure/Error: DhanHQ::Models::Order.create(payload)

      DhanHQ::Error:
        Market is closed
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:682:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  46) Order Placement Integration Error Handling and Resilience when handling order placement failures handles invalid instrument errors
      Failure/Error: DhanHQ::Models::Order.create(payload)

      DhanHQ::Error:
        Invalid security ID
      # ./app/services/orders/placer.rb:58:in `block in buy_market!'
      # ./app/services/orders/token_bucket.rb:20:in `block in consume!'
      # ./app/services/orders/token_bucket.rb:18:in `consume!'
      # ./app/services/orders/placer.rb:390:in `with_order_rate_limit'
      # ./app/services/orders/placer.rb:57:in `buy_market!'
      # ./spec/integration/order_placement_spec.rb:700:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  47) Trend Duration Indicator Integration integration with MultiIndicatorStrategy works with MultiIndicatorStrategy
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            {
              type: 'trend_duration',
              config: {
                hma_length: 20,
                trend_length: 5,
                samples: 10
              }

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/trend_duration_indicator_integration_spec.rb:123:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  48) Trend Duration Indicator Integration integration with MultiIndicatorStrategy combines with other indicators
      Failure/Error:
        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: [
            {
              type: 'supertrend',
              config: { period: 7, multiplier: 3.0 }
            },
            {
              type: 'trend_duration',
              config: {

      NameError:
        uninitialized constant MultiIndicatorStrategy
      # ./spec/integration/trend_duration_indicator_integration_spec.rb:152:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  49) CandleExtension#ohlc_stale? updates last_ohlc_fetched timestamp
      Failure/Error: expect(instrument.instance_variable_get(:@last_ohlc_fetched)['5']).to be_within(1.second).of(Time.current)
        expected nil to be within 1 of 2026-06-24 20:28:47.315478654 +0530, but it could not be treated as a numeric value
      # ./spec/models/concerns/candle_extension_spec.rb:285:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  50) Derivative#buy_option! when quantity is provided uses provided quantity and places order
      Failure/Error:
        tracker = after_order_track!(
          instrument: instrument,
          order_no: order.order_id,
          segment: segment_code,
          security_id: security,
          side: side_label,
          qty: quantity,
          entry_price: ltp,
          symbol: symbol_name || display_name,
          index_key: (index_cfg || {})[:key],

        #<Derivative id: 17, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:29:07.825663000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 292, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:29:07.825663000 +0530"> received :after_order_track! with unexpected arguments
          expected: ({:entry_price=>0.12075e3, :index_key=>nil, :instrument=>#<Instrument id: 292, asm_gsm_category: nil, ...RD654321", :qty=>50, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"long_ce", :symbol=>"NIFTY"})
               got: ({:entry_price=>0.12075e3, :index_key=>nil, :instrument=>#<Instrument id: 292, asm_gsm_category: nil, ...RD654321", :qty=>50, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"long_ce", :symbol=>"NIFTY"})
        Diff:
        @@ -2,6 +2,7 @@
           :index_key=>nil,
           :instrument=>
            #<Instrument id: 292, asm_gsm_category: nil, asm_gsm_flag: nil, bracket_flag: nil, buy_bo_min_margin_per: nil, buy_bo_profit_range_max_perc: nil, buy_bo_profit_range_min_perc: nil, buy_bo_sl_range_max_perc: nil, buy_bo_sl_range_min_perc: nil, buy_co_min_margin_per: nil, buy_co_sl_range_max_perc: nil, buy_co_sl_range_min_perc: nil, buy_sell_indicator: nil, cover_flag: nil, created_at: "2026-06-24 20:29:07.812002000 +0530", display_name: nil, exchange: "nse", expiry_date: nil, expiry_flag: nil, instrument_code: "index", instrument_type: "INDEX", isin: nil, lot_size: nil, mtf_leverage: nil, option_type: nil, security_id: "13", segment: "index", sell_bo_min_margin_per: nil, sell_bo_profit_range_max_perc: nil, sell_bo_profit_range_min_perc: nil, sell_bo_sl_min_range: nil, sell_bo_sl_range_max_perc: nil, sell_co_min_margin_per: nil, sell_co_sl_range_max_perc: nil, sell_co_sl_range_min_perc: nil, series: nil, strike_price: nil, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: nil, underlying_symbol: nil, updated_at: "2026-06-24 20:29:07.812002000 +0530">,
        +  :meta=>{},
           :order_no=>"ORD654321",
           :qty=>50,
           :security_id=>"60001",

      # ./app/models/derivative.rb:159:in `buy_option!'
      # ./spec/models/derivative_spec.rb:121:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  51) Derivative#buy_option! when quantity is nil or zero calculates quantity via Capital::Allocator
      Failure/Error:
        expect(Orders.config.gateway).to receive(:place_market).with(
          side: 'buy',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          qty: 75,
          meta: hash_including(:client_order_id, ltp: BigDecimal('120.75'), product_type: 'INTRADAY')
        ).and_return(order_response)

        #<Orders::GatewayPaper:0x00007f12d8af2840> received :place_market with unexpected arguments
          expected: ({:meta=>hash_including(:ltp=>0.12075e3, :product_type=>"INTRADAY", :client_order_id=>"anything"), :qty=>75, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"buy"}) (keyword arguments)
               got: ({:meta=>{:client_order_id=>"AS-BUY-60001-313147", :ltp=>0.12075e3, :product_type=>"NORMAL"}, :qty=>75, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"buy"}) (options hash)
        Diff:
        @@ -1,5 +1,7 @@
         [{:meta=>
        -   hash_including(:ltp=>0.12075e3, :product_type=>"INTRADAY", :client_order_id=>"anything"),
        +   {:client_order_id=>"AS-BUY-60001-313147",
        +    :ltp=>0.12075e3,
        +    :product_type=>"NORMAL"},
           :qty=>75,
           :security_id=>"60001",
           :segment=>"NSE_FNO",

      # ./spec/models/derivative_spec.rb:131:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  52) Derivative#buy_option! when quantity is nil or zero includes index_key in tracker when index_cfg provided
      Failure/Error:
        tracker = after_order_track!(
          instrument: instrument,
          order_no: order.order_id,
          segment: segment_code,
          security_id: security,
          side: side_label,
          qty: quantity,
          entry_price: ltp,
          symbol: symbol_name || display_name,
          index_key: (index_cfg || {})[:key],

        #<Derivative id: 19, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:29:07.894852000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 294, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:29:07.894852000 +0530"> received :after_order_track! with unexpected arguments
          expected: ({:entry_price=>0.12075e3, :index_key=>"NIFTY", :instrument=>#<Instrument id: 294, asm_gsm_category: n...RD654321", :qty=>75, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"long_ce", :symbol=>"NIFTY"})
               got: ({:entry_price=>0.12075e3, :index_key=>"NIFTY", :instrument=>#<Instrument id: 294, asm_gsm_category: n...RD654321", :qty=>75, :security_id=>"60001", :segment=>"NSE_FNO", :side=>"long_ce", :symbol=>"NIFTY"})
        Diff:
        @@ -2,6 +2,7 @@
           :index_key=>"NIFTY",
           :instrument=>
            #<Instrument id: 294, asm_gsm_category: nil, asm_gsm_flag: nil, bracket_flag: nil, buy_bo_min_margin_per: nil, buy_bo_profit_range_max_perc: nil, buy_bo_profit_range_min_perc: nil, buy_bo_sl_range_max_perc: nil, buy_bo_sl_range_min_perc: nil, buy_co_min_margin_per: nil, buy_co_sl_range_max_perc: nil, buy_co_sl_range_min_perc: nil, buy_sell_indicator: nil, cover_flag: nil, created_at: "2026-06-24 20:29:07.881929000 +0530", display_name: nil, exchange: "nse", expiry_date: nil, expiry_flag: nil, instrument_code: "index", instrument_type: "INDEX", isin: nil, lot_size: nil, mtf_leverage: nil, option_type: nil, security_id: "13", segment: "index", sell_bo_min_margin_per: nil, sell_bo_profit_range_max_perc: nil, sell_bo_profit_range_min_perc: nil, sell_bo_sl_min_range: nil, sell_bo_sl_range_max_perc: nil, sell_co_min_margin_per: nil, sell_co_sl_range_max_perc: nil, sell_co_sl_range_min_perc: nil, series: nil, strike_price: nil, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: nil, underlying_symbol: nil, updated_at: "2026-06-24 20:29:07.881929000 +0530">,
        +  :meta=>{},
           :order_no=>"ORD654321",
           :qty=>75,
           :security_id=>"60001",

      # ./app/models/derivative.rb:159:in `buy_option!'
      # ./spec/models/derivative_spec.rb:168:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  53) Instrument#buy_market! when quantity is provided uses provided quantity and places order
      Failure/Error:
        after_order_track!(
          instrument: self,
          order_no: order.order_id,
          segment: segment_code,
          security_id: security,
          side: "LONG",
          qty: quantity,
          entry_price: ltp,
          symbol: symbol_name || display_name,
          index_key: meta[:index_key],

        #<Instrument id: 310, asm_gsm_category: nil, asm_gsm_flag: nil, bracket_flag: nil, buy_bo_min_margin_per: nil, buy_bo_profit_range_max_perc: nil, buy_bo_profit_range_min_perc: nil, buy_bo_sl_range_max_perc: nil, buy_bo_sl_range_min_perc: nil, buy_co_min_margin_per: nil, buy_co_sl_range_max_perc: nil, buy_co_sl_range_min_perc: nil, buy_sell_indicator: nil, cover_flag: nil, created_at: "2026-06-24 20:30:08.683654000 +0530", display_name: nil, exchange: "nse", expiry_date: nil, expiry_flag: nil, instrument_code: "index", instrument_type: "INDEX", isin: nil, lot_size: nil, mtf_leverage: nil, option_type: nil, security_id: "13", segment: "index", sell_bo_min_margin_per: nil, sell_bo_profit_range_max_perc: nil, sell_bo_profit_range_min_perc: nil, sell_bo_sl_min_range: nil, sell_bo_sl_range_max_perc: nil, sell_co_min_margin_per: nil, sell_co_sl_range_max_perc: nil, sell_co_sl_range_min_perc: nil, series: nil, strike_price: nil, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: nil, underlying_symbol: nil, updated_at: "2026-06-24 20:30:08.683654000 +0530"> received :after_order_track! with unexpected arguments
          expected: ({:entry_price=>0.2005e3, :instrument=>#<Instrument id: 310, asm_gsm_category: nil, asm_gsm_flag: nil,...er_no=>"ORD123456", :qty=>2, :security_id=>"13", :segment=>"IDX_I", :side=>"LONG", :symbol=>"NIFTY"})
               got: ({:entry_price=>0.2005e3, :index_key=>nil, :instrument=>#<Instrument id: 310, asm_gsm_category: nil, a...er_no=>"ORD123456", :qty=>2, :security_id=>"13", :segment=>"IDX_I", :side=>"LONG", :symbol=>"NIFTY"})
        Diff:

        @@ -1,6 +1,8 @@
         [{:entry_price=>0.2005e3,
        +  :index_key=>nil,
           :instrument=>
            #<Instrument id: 310, asm_gsm_category: nil, asm_gsm_flag: nil, bracket_flag: nil, buy_bo_min_margin_per: nil, buy_bo_profit_range_max_perc: nil, buy_bo_profit_range_min_perc: nil, buy_bo_sl_range_max_perc: nil, buy_bo_sl_range_min_perc: nil, buy_co_min_margin_per: nil, buy_co_sl_range_max_perc: nil, buy_co_sl_range_min_perc: nil, buy_sell_indicator: nil, cover_flag: nil, created_at: "2026-06-24 20:30:08.683654000 +0530", display_name: nil, exchange: "nse", expiry_date: nil, expiry_flag: nil, instrument_code: "index", instrument_type: "INDEX", isin: nil, lot_size: nil, mtf_leverage: nil, option_type: nil, security_id: "13", segment: "index", sell_bo_min_margin_per: nil, sell_bo_profit_range_max_perc: nil, sell_bo_profit_range_min_perc: nil, sell_bo_sl_min_range: nil, sell_bo_sl_range_max_perc: nil, sell_co_min_margin_per: nil, sell_co_sl_range_max_perc: nil, sell_co_sl_range_min_perc: nil, series: nil, strike_price: nil, symbol_name: "NIFTY", tick_size: nil, underlying_security_id: nil, underlying_symbol: nil, updated_at: "2026-06-24 20:30:08.683654000 +0530">,
        +  :meta=>{},
           :order_no=>"ORD123456",
           :qty=>2,
           :security_id=>"13",

      # ./app/models/instrument.rb:180:in `buy_market!'
      # ./spec/models/instrument_spec.rb:113:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  54) GET /api/dashboard includes pnl_updater_running in the system hash
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:33:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  55) GET /api/dashboard reflects pnl_updater_running as false when service is stopped
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:41:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  56) GET /api/dashboard includes subscribed_indices as an array
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:48:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  57) GET /api/dashboard includes market_status with expected keys
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:55:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  58) GET /api/dashboard when SMC confluence digest is enabled includes smc_confluence_ltf from analysis store on subscribed_indices
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:105:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  59) GET /api/dashboard when SMC confluence digest is enabled exposes confluence flags in config.signals
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:114:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  60) GET /api/dashboard when SMC confluence digest is disabled omits smc_confluence_ltf on subscribed_indices
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:155:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  61) GET /api/dashboard when watchlist index segment differs from feed segment IDX_I falls back to IDX_I + sid for index LTP on indices payload
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/requests/api/dashboard_spec.rb:175:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  62) OpenAPI v1 — infrastructure & dashboard reads /api/dashboard get dashboard JSON returns a 200 response
      Failure/Error:
        TradingSignal.order(created_at: :desc).limit(10).map do |signal|
          signal.as_json(methods: [:confidence_level]).merge(
            'metadata' => signal.effective_metadata
          )
        end

        #<Double (anonymous)> received unexpected message :map with (no args)
      # ./app/controllers/api/dashboard_controller.rb:49:in `recent_signals_payload'
      # ./app/controllers/api/dashboard_controller.rb:21:in `show'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine/lazy_route_set.rb:60:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/bullet-8.1.3/lib/bullet/rack.rb:18:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-attack-6.8.0/lib/rack/attack.rb:105:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/etag.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/conditional_get.rb:31:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/head.rb:15:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:41:in `call_app'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/rack/logger.rb:29:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/runtime.rb:24:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-3.2.6/lib/rack/sendfile.rb:131:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-cors-3.0.0/lib/rack/cors.rb:102:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/engine.rb:534:in `call'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:360:in `process_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rack-test-2.2.0/lib/rack/test.rb:153:in `request'
      # ./spec/support/rswag_rails_json_request.rb:29:in `submit_request'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/rswag-specs-2.17.0/lib/rswag/specs/example_group_helpers.rb:140:in `block in run_test!'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
      # ./spec/support/api_token_request_isolation.rb:11:in `block (2 levels) in <top (required)>'

  63) Entries::EntryGuard.post_entry_wiring subscribes option strikes and adds to ActiveCache when feature flag enabled
      Failure/Error: described_class.send(:post_entry_wiring, tracker: option_tracker, side: 'long_ce', index_cfg: {})

      NoMethodError:
        undefined method `post_entry_wiring' for class Entries::EntryGuard
      # ./spec/services/entries/entry_guard_autowire_spec.rb:61:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  64) Entries::EntryGuard.post_entry_wiring skips subscription for non-option segments but still adds to ActiveCache
      Failure/Error: described_class.send(:post_entry_wiring, tracker: equity_tracker, side: 'long_ce', index_cfg: {})

      NoMethodError:
        undefined method `post_entry_wiring' for class Entries::EntryGuard
      # ./spec/services/entries/entry_guard_autowire_spec.rb:71:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  65) Entries::EntryGuard.post_entry_wiring does not autowire when feature flag disabled but still places bracket
      Failure/Error: described_class.send(:post_entry_wiring, tracker: option_tracker, side: 'long_ce', index_cfg: {})

      NoMethodError:
        undefined method `post_entry_wiring' for class Entries::EntryGuard
      # ./spec/services/entries/entry_guard_autowire_spec.rb:81:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  66) Entries::EntryGuard#try_enter signal recording when DrawdownGuard is triggered records skipped with drawdown_guard_active reason
      Failure/Error: expect(signal.reload.metadata['entry_outcome']).to eq('skipped')

        expected: "skipped"
             got: "blocked"

        (compared using ==)
      # ./spec/services/entries/entry_guard_signal_recording_spec.rb:40:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  67) Entries::EntryGuard#try_enter signal recording when entry succeeds (entered outcome) the entered recording line is present in try_enter source
      Failure/Error: expect(content).to include("signal&.record_entry_outcome('entered') if tracker")

        expected "# frozen_string_literal: true\n\nrequire_relative '../concerns/broker_fee_calculator'\nrequire_relat...xt, entry_metadata, entry_price: entry_price, quantity: quantity)\n      end\n    end\n  end\nend\n" to include "signal&.record_entry_outcome('entered') if tracker"
        Diff:
        @@ -1 +1,252 @@
        -signal&.record_entry_outcome('entered') if tracker
        +# frozen_string_literal: true
        +
        +require_relative '../concerns/broker_fee_calculator'
        +require_relative 'bos_extractor'
        +
        +module Entries
        +  class EntryGuard
        +    ENTRY_CONTRACT = 'bos_machine_v1'
        +    SUPERTREND_CONTRACT = 'supertrend_machine_v1'
        +
        +    class << self
        +      include Live::UnderlyingLtpResolver
        +
        +      def entry_guard_pipeline
        +        @entry_guard_pipeline ||= EntryGuardPipeline.new
        +      end
        +
        +      def try_enter(index_cfg:, pick:, direction:, scale_multiplier: 1, entry_metadata: nil, permission: nil, signal: nil)
        +        # 1. Pipeline Execution
        +        context = {
        +          index_cfg: index_cfg,
        +          pick: pick,
        +          direction: direction,
        +          scale_multiplier: scale_multiplier,
        +          entry_metadata: entry_metadata || {},
        +          permission: permission,
        +          is_paper: entry_metadata&.dig(:paper) || Rails.env.local?
        +        }
        +
        +        result = entry_guard_pipeline.run(context)
        +        if result != EntryGuardPipeline::PASS
        +          reason = result.is_a?(Hash) ? result[:blocked] : result.to_s
        +          Observability::StructuredLog.info(
        +            event: 'entry_blocked',
        +            payload: {
        +              service: 'Entries::EntryGuard',
        +              index_key: index_cfg[:key].to_s,
        +              symbol: pick[:symbol].to_s,
        +              reason: reason
        +            }
        +          )
        +          signal&.record_entry_outcome('blocked', reason)
        +          return false
        +        end
        +
        +        # 2. Order Execution
        +        execution_result = OrderExecutionService.call(context)
        +
        +        if execution_result.is_a?(Hash) && execution_result[:error]
        +          signal&.record_entry_outcome('blocked', execution_result[:error])
        +          return false
        +        end
        +
        +        # Success - Tracker created
        +        signal&.record_entry_outcome('entered')
        +        true
        +      rescue StandardError => e
        +        signal&.record_entry_outcome('blocked', "exception: #{e.class}")
        +        bt = e.backtrace&.first(12)&.join("\n")
        +        msg = "EntryGuard failed for #{index_cfg[:key]}: #{e.class} - #{e.message}"
        +        msg = "#{msg}\n#{bt}" if bt.present?
        +        Rails.logger.error(msg)
        +        false
        +      end
        +
        +      # Used by OrderExecutionService
        +      def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:, entry_metadata:, bos_context:)
        +        meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
        +        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)
        +
        +        snapshot = meta_hash.delete('config_snapshot')
        +        version = meta_hash.delete('config_version') || {}
        +        entry_at = meta_hash.delete('entry_at')
        +
        +        tracker = PositionTracker.create!(
        +          order_no: order_no,
        +          instrument: instrument,
        +          watchable: instrument,
        +          symbol: pick[:symbol],
        +          security_id: pick[:security_id],
        +          segment: pick[:segment] || index_cfg[:segment],
        +          side: side,
        +          quantity: quantity,
        +          entry_price: ltp,
        +          avg_price: ltp,
        +          status: :active,
        +          paper: false,
        +          meta: meta_hash
        +        )
        +
        +        tracker.create_position_meta_snapshot!(
        +          config_version_hash: version['hash'].to_s,
        +          config_change_log_id: version['change_log_id'],
        +          config_snapshot: snapshot,
        +          entry_at: entry_at
        +        )
        +
        +        tracker
        +      end
        +
        +      def create_paper_tracker!(instrument:, pick:, side:, quantity:, index_cfg:, ltp:, order_no:, entry_metadata:, bos_context:)
        +        meta_hash = build_base_meta(index_cfg: index_cfg, pick: pick, direction: bos_context&.dig(:direction))
        +        apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price: ltp, quantity: quantity)
        +
        +        snapshot = meta_hash.delete('config_snapshot')
        +        version = meta_hash.delete('config_version') || {}
        +
        +        tracker = PositionTracker.create!(
        +          order_no: order_no,
        +          instrument: instrument,
        +          watchable: instrument,
        +          symbol: pick[:symbol],
        +          security_id: pick[:security_id],
        +          segment: pick[:segment] || index_cfg[:segment],
        +          side: side,
        +          quantity: quantity,
        +          entry_price: ltp,
        +          avg_price: ltp,
        +          status: :active,
        +          paper: true,
        +          meta: meta_hash
        +        )
        +
        +        tracker.create_position_meta_snapshot!(
        +          config_version_hash: version['hash'].to_s,
        +          config_change_log_id: version['change_log_id'],
        +          config_snapshot: snapshot
        +        )
        +
        +        tracker
        +      end
        +
        +      def build_client_order_id(index_cfg:, pick:)
        +        "#{index_cfg[:key]}_#{pick[:symbol]}_#{Time.current.to_i}"
        +      end
        +
        +      def find_instrument(index_cfg)
        +        Instrument.find_by_sid_and_segment(
        +          security_id: index_cfg[:sid],
        +          segment_code: index_cfg[:segment]
        +        )
        +      end
        +
        +      def cooldown_active_for_index?(index_key, cooldown)
        +        return false if index_key.blank? || cooldown <= 0
        +
        +        last = Rails.cache.read("reentry:index:#{index_key}")
        +        last.present? && (Time.current - last) < cooldown
        +      end
        +
        +      # BANKNIFTY trades only in the last week before monthly expiry.
        +      # Uses instrument expiry_list to find the actual monthly expiry date (holiday-aware).
        +      # Falls back to last-Thursday-of-month calculation only when expiry_list is unavailable.
        +      # Returns true if today is within 7 calendar days of the nearest upcoming monthly expiry.
        +      def banknifty_last_week?(instrument: nil)
        +        today          = Time.zone.today
        +        monthly_expiry = banknifty_monthly_expiry(instrument, today)
        +        return false unless monthly_expiry
        +
        +        days_to_expiry = (monthly_expiry - today).to_i
        +        days_to_expiry.between?(0, 6)
        +      rescue StandardError => e
        +        Rails.logger.error("[EntryGuard] banknifty_last_week? error: #{e.message}")
        +        false
        +      end
        +
        +      def extract_order_no(response)
        +        Ledger::OrderResponse.extract_order_id(response) || legacy_extract_order_no(response)
        +      end
        +
        +      def legacy_extract_order_no(response)
        +        return response[:order_id] || response['order_id'] if response.is_a?(Hash)
        +
        +        response
        +      end
        +
        +      def timeframe_to_interval(timeframe)
        +        return nil if timeframe.blank?
        +        str = timeframe.to_s.strip.downcase
        +        return nil if str.empty?
        +        if str.end_with?('h')
        +          hours = str.gsub(/[^0-9]/, '').to_i
        +          return nil if hours <= 0
        +          return hours * 60
        +        end
        +        str.gsub(/[^0-9]/, '').to_i
        +      end
        +
        +      private
        +
        +      def banknifty_monthly_expiry(instrument, today)
        +        expiry_list = instrument&.expiry_list&.compact
        +        if expiry_list.present?
        +          parsed = expiry_list.filter_map do |raw|
        +            case raw
        +            when Date then raw
        +            when String
        +              begin
        +                Date.parse(raw)
        +              rescue ArgumentError, TypeError
        +                nil
        +              end
        +            when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
        +            end
        +          end.sort
        +
        +          monthly_expiries = parsed.group_by { |d| [d.year, d.month] }
        +                                   .map { |_, dates| dates.max }
        +                                   .sort
        +
        +          nearest = monthly_expiries.find { |d| d >= today }
        +          return nearest if nearest
        +        end
        +
        +        # Fallback: last Thursday of month
        +        last_day = today.end_of_month
        +        last_thu = last_day - ((last_day.wday - 4) % 7).days
        +        if last_thu < today
        +          last_day = (today + 1.month).end_of_month
        +          last_thu = last_day - ((last_day.wday - 4) % 7).days
        +        end
        +        last_thu
        +      end
        +
        +      def build_base_meta(index_cfg:, pick:, direction:)
        +        snapshot_fields = Entries::EntrySnapshotBuilder.build(index_cfg: index_cfg, pick: pick)
        +
        +        {
        +          index_key: index_cfg[:key].to_s,
        +          symbol: pick[:symbol].to_s,
        +          direction: direction || pick[:direction],
        +          entry_at: Time.current.iso8601,
        +          config_version: AlgoConfig.version,
        +          config_snapshot: snapshot_fields[:config_snapshot],
        +          dte_at_entry: snapshot_fields[:dte_at_entry],
        +          vix_at_entry: snapshot_fields[:vix_at_entry],
        +          iv_at_entry: pick[:iv] || pick['iv'] || pick[:implied_volatility] || pick['implied_volatility'],
        +          spread_guard_pct: snapshot_fields[:spread_guard_pct],
        +          atm_strike: snapshot_fields[:atm_strike],
        +          expiry_date: snapshot_fields[:expiry_date],
        +          entry_context: snapshot_fields[:entry_context]
        +        }
        +      end
        +
        +      def apply_bos_metadata!(meta_hash, bos_context, entry_metadata, entry_price:, quantity:)
        +        # Simplification: logic moved partially to service, but meta building kept here for now
        +        # Call the existing implementation or refactor it into a dedicated MetaBuilder
        +        Entries::MetaBuilder.call(meta_hash, bos_context, entry_metadata, entry_price: entry_price, quantity: quantity)
        +      end
        +    end
        +  end
        +end

      # ./spec/services/entries/entry_guard_signal_recording_spec.rb:115:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  68) Entries::Guards::ExpiryWeekPowerTrendGuard when instrument is nil (no expiry list available) passes without enriching context (cannot confirm expiry week)
      Failure/Error: expect(context[:expiry_power_trend]).to be_nil

        expected: nil
             got: true
      # ./spec/services/entries/guards/expiry_week_power_trend_guard_spec.rb:123:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  69) Entries::Guards::LtpResolutionGuard uses fresh tick cache LTP for entry even when pick contains ltp
      Failure/Error:
        MarketTick.new(
          segment: 'NSE_FNO',
          security_id: '50074',
          ltp: BigDecimal(ltp.to_s),
          timestamp: Time.current - age_seconds,
          oi: 0,
          oi_change: 0,
          bid: nil,
          ask: nil,
          volume: 0,

      ArgumentError:
        missing keywords: :bid_qty, :ask_qty
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `initialize'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `new'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `build_tick'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:17:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  70) Entries::Guards::LtpResolutionGuard accepts tick after forced refresh when subscribe yields no fresh tick but cache updates
      Failure/Error:
        MarketTick.new(
          segment: 'NSE_FNO',
          security_id: '50074',
          ltp: BigDecimal(ltp.to_s),
          timestamp: Time.current - age_seconds,
          oi: 0,
          oi_change: 0,
          bid: nil,
          ask: nil,
          volume: 0,

      ArgumentError:
        missing keywords: :bid_qty, :ask_qty
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `initialize'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `new'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `build_tick'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:30:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  71) Entries::Guards::LtpResolutionGuard accepts REST snapshot when tick cache stays stale
      Failure/Error:
        MarketTick.new(
          segment: 'NSE_FNO',
          security_id: '50074',
          ltp: BigDecimal(ltp.to_s),
          timestamp: Time.current - age_seconds,
          oi: 0,
          oi_change: 0,
          bid: nil,
          ask: nil,
          volume: 0,

      ArgumentError:
        missing keywords: :bid_qty, :ask_qty
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `initialize'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `new'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `build_tick'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:44:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  72) Entries::Guards::LtpResolutionGuard accepts websocket_fresh resolution when re-read tick lags
      Failure/Error:
        MarketTick.new(
          segment: 'NSE_FNO',
          security_id: '50074',
          ltp: BigDecimal(ltp.to_s),
          timestamp: Time.current - age_seconds,
          oi: 0,
          oi_change: 0,
          bid: nil,
          ask: nil,
          volume: 0,

      ArgumentError:
        missing keywords: :bid_qty, :ask_qty
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `initialize'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `new'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `build_tick'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:57:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  73) Entries::Guards::LtpResolutionGuard blocks entry when no fresh tick and no usable resolution
      Failure/Error:
        MarketTick.new(
          segment: 'NSE_FNO',
          security_id: '50074',
          ltp: BigDecimal(ltp.to_s),
          timestamp: Time.current - age_seconds,
          oi: 0,
          oi_change: 0,
          bid: nil,
          ask: nil,
          volume: 0,

      ArgumentError:
        missing keywords: :bid_qty, :ask_qty
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `initialize'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `new'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:78:in `build_tick'
      # ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:68:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  74) Entries::NoTradeContextBuilder.build sets correct IV threshold for NIFTY
      Failure/Error: expect(ctx.min_iv_threshold).to eq(10)

        expected: 10
             got: 9

        (compared using ==)
      # ./spec/services/entries/no_trade_context_builder_spec.rb:88:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  75) Entries::NoTradeContextBuilder.build sets correct IV threshold for BANKNIFTY
      Failure/Error: expect(ctx.min_iv_threshold).to eq(13)

        expected: 13
             got: 9

        (compared using ==)
      # ./spec/services/entries/no_trade_context_builder_spec.rb:100:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  76) Entries::NoTradeContextBuilder.build when ADX calculation fails falls back to simple ADX value
      Failure/Error: adx_data = calculate_adx_data(bars_5m)

      StandardError:
        ADX error
      # ./app/services/entries/no_trade_context_builder.rb:31:in `build'
      # ./spec/services/entries/no_trade_context_builder_spec.rb:168:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  77) Entries::NoTradeContextBuilder.build when bars_5m has insufficient data returns zero ADX values
      Failure/Error: expect(ctx.adx_5m).to eq(0)

        expected: 0
             got: 20.0

        (compared using ==)
      # ./spec/services/entries/no_trade_context_builder_spec.rb:194:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  78) Entries::NoTradeEngine.validate when score is below threshold (score < 3) allows trade when only 1 condition is triggered
      Failure/Error: expect(result.score).to eq(1)

        expected: 1
             got: 0.5

        (compared using ==)
      # ./spec/services/entries/no_trade_engine_spec.rb:62:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  79) Entries::NoTradeEngine.validate when score is below threshold (score < 3) allows trade when only 2 conditions are triggered
      Failure/Error: expect(result.score).to eq(2)

        expected: 2
             got: 1.5

        (compared using ==)
      # ./spec/services/entries/no_trade_engine_spec.rb:90:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  80) Entries::NoTradeEngine.validate when score reaches threshold (score >= 3) blocks trade when 3 conditions are triggered
      Failure/Error: expect(result.allowed).to be false

        expected false
             got true
      # ./spec/services/entries/no_trade_engine_spec.rb:120:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  81) Entries::NoTradeEngine.validate trend weakness checks blocks when ADX < 15
      Failure/Error: expect(result.reasons).to include('Weak trend: ADX < 15')
        expected ["Moderate trend: ADX 14 < 18"] to include "Weak trend: ADX < 15"
      # ./spec/services/entries/no_trade_engine_spec.rb:180:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  82) Entries::NoTradeEngine.validate trend weakness checks blocks when DI overlap < 2
      Failure/Error: expect(result.reasons).to include('DI overlap: no directional strength')
        expected ["DI overlap: no directional strength (diff: 1 < 2.0)"] to include "DI overlap: no directional strength"
      # ./spec/services/entries/no_trade_engine_spec.rb:232:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  83) Entries::NoTradeEngine.validate VWAP checks blocks when near VWAP
      Failure/Error: expect(result.reasons).to include('VWAP magnet zone')
        expected ["VWAP magnet zone (within ±0.08%)"] to include "VWAP magnet zone"
      # ./spec/services/entries/no_trade_engine_spec.rb:366:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  84) Entries::NoTradeEngine.validate volatility checks blocks when 10-minute range < 0.1%
      Failure/Error: expect(result.reasons).to include('Low volatility: 10m range < 0.1%')
        expected ["Low volatility: 10m range 0.05% < 0.06%"] to include "Low volatility: 10m range < 0.1%"
      # ./spec/services/entries/no_trade_engine_spec.rb:420:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  85) Entries::NoTradeEngine.validate volatility checks blocks when ATR is trending down
      Failure/Error: expect(result.reasons).to include('ATR decreasing (volatility compression)')
        expected ["ATR decreasing (volatility compression for 5+ bars)"] to include "ATR decreasing (volatility compression)"
      # ./spec/services/entries/no_trade_engine_spec.rb:446:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  86) Entries::NoTradeEngine.validate option chain checks blocks when both CE & PE OI are rising
      Failure/Error: expect(result.reasons).to include('Both CE & PE OI rising (writers controlling)')
        expected [] to include "Both CE & PE OI rising (writers controlling)"
      # ./spec/services/entries/no_trade_engine_spec.rb:474:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  87) Entries::NoTradeEngine.validate option chain checks blocks when spread is wide
      Failure/Error: expect(result.reasons).to include('Wide bid-ask spread')
        expected ["Wide bid-ask spread (> ₹3)"] to include "Wide bid-ask spread"
      # ./spec/services/entries/no_trade_engine_spec.rb:552:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  88) Entries::NoTradeEngine.validate candle quality checks blocks when wick ratio > 1.8
      Failure/Error: expect(result.reasons).to include(match(/High wick ratio/))

        expected ["Moderate wick ratio: 2.0 > 1.8"] to include (match /High wick ratio/)
        Diff:
        @@ -1 +1 @@
        -[(match /High wick ratio/)]
        +["Moderate wick ratio: 2.0 > 1.8"]

      # ./spec/services/entries/no_trade_engine_spec.rb:580:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  89) Entries::NoTradeEngine.validate time window checks blocks during lunch-time if ADX < 20
      Failure/Error: expect(result.reasons).to include('Lunch-time theta zone (weak trend)')
        expected [] to include "Lunch-time theta zone (weak trend)"
      # ./spec/services/entries/no_trade_engine_spec.rb:634:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  90) Entries::RangeUtils.compressed? returns true when range is below threshold
      Failure/Error: expect(result).to be true

        expected true
             got false
      # ./spec/services/entries/range_utils_spec.rb:52:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  91) Entries::StructureDetector.bos? with valid data respects lookback_minutes parameter
      Failure/Error: bars.last.close = 26_000 # Breaks high, but outside lookback

      NoMethodError:
        undefined method `close=' for an instance of Candle
      # ./spec/services/entries/structure_detector_spec.rb:48:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  92) Entries::StructureDetector.inside_opposite_ob? with valid data detects when price is inside opposite Order Block
      Failure/Error: expect(result).to be true

        expected true
             got false
      # ./spec/services/entries/structure_detector_spec.rb:95:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  93) Entries::StructureDetector.inside_fvg? with valid data detects when price is inside opposing Fair Value Gap
      Failure/Error: expect(result).to be true

        expected true
             got false
      # ./spec/services/entries/structure_detector_spec.rb:138:in `block (4 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  94) Entries::VWAPUtils.calculate_avwap calculates AVWAP from anchor time
      Failure/Error: expect(avwap).to be_within(1).of(25_050)
        expected 25058.333333333336 to be within 1 of 25050
      # ./spec/services/entries/vwap_utils_spec.rb:88:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  95) Indicators::AdxIndicator#initialize initializes with series and config
      Failure/Error:
        def initialize(timestamp:, open:, high:, low:, close:, volume:)
          @timestamp = timestamp
          @open = open.to_f
          @high = high.to_f
          @low = low.to_f
          @close = close.to_f
          @volume = volume.to_i
        end

      ArgumentError:
        missing keyword: :timestamp
      # ./app/models/candle.rb:7:in `initialize'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
      # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  96) Indicators::AdxIndicator#initialize uses default config when not provided
      Failure/Error:
        def initialize(timestamp:, open:, high:, low:, close:, volume:)
          @timestamp = timestamp
          @open = open.to_f
          @high = high.to_f
          @low = low.to_f
          @close = close.to_f
          @volume = volume.to_i
        end

      ArgumentError:
        missing keyword: :timestamp
      # ./app/models/candle.rb:7:in `initialize'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
      # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  97) Indicators::AdxIndicator#min_required_candles returns minimum candles required for ADX
      Failure/Error:
        def initialize(timestamp:, open:, high:, low:, close:, volume:)
          @timestamp = timestamp
          @open = open.to_f
          @high = high.to_f
          @low = low.to_f
          @close = close.to_f
          @volume = volume.to_i
        end

      ArgumentError:
        missing keyword: :timestamp
      # ./app/models/candle.rb:7:in `initialize'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
      # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  98) Indicators::AdxIndicator#ready? returns false when not enough candles
      Failure/Error:
        def initialize(timestamp:, open:, high:, low:, close:, volume:)
          @timestamp = timestamp
          @open = open.to_f
          @high = high.to_f
          @low = low.to_f
          @close = close.to_f
          @volume = volume.to_i
        end

      ArgumentError:
        missing keyword: :timestamp
      # ./app/models/candle.rb:7:in `initialize'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
      # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  99) Indicators::AdxIndicator#ready? returns true when enough candles
      Failure/Error:
        def initialize(timestamp:, open:, high:, low:, close:, volume:)
          @timestamp = timestamp
          @open = open.to_f
          @high = high.to_f
          @low = low.to_f
          @close = close.to_f
          @volume = volume.to_i
        end

      ArgumentError:
        missing keyword: :timestamp
      # ./app/models/candle.rb:7:in `initialize'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
      # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
      # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
      # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
      # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
      # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  100) Indicators::AdxIndicator#calculate_at returns hash with required keys
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  101) Indicators::AdxIndicator#calculate_at uses CandleSeries#adx for calculation
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  102) Indicators::AdxIndicator#calculate_at returns direction based on price movement
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  103) Indicators::AdxIndicator#calculate_at returns confidence based on ADX strength
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  104) Indicators::AdxIndicator#calculate_at filters weak ADX values below min_strength
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/adx_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/adx_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  105) Indicators::BaseIndicator#trading_hours? when trading_hours_filter is enabled returns true for candles within trading hours
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/base_indicator_spec.rb:66:in `new'
       # ./spec/services/indicators/base_indicator_spec.rb:66:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  106) Indicators::BaseIndicator#trading_hours? when trading_hours_filter is enabled returns false for candles outside trading hours
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/base_indicator_spec.rb:78:in `new'
       # ./spec/services/indicators/base_indicator_spec.rb:78:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  107) Indicators::BaseIndicator#trading_hours? when trading_hours_filter is disabled returns true for all candles
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/base_indicator_spec.rb:94:in `new'
       # ./spec/services/indicators/base_indicator_spec.rb:94:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  108) Indicators::MacdIndicator#initialize initializes with series and config
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  109) Indicators::MacdIndicator#min_required_candles returns minimum candles required for MACD
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  110) Indicators::MacdIndicator#calculate_at returns hash with required keys
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  111) Indicators::MacdIndicator#calculate_at uses CandleSeries#macd for calculation
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  112) Indicators::MacdIndicator#calculate_at returns bullish direction when MACD crosses above signal
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  113) Indicators::MacdIndicator#calculate_at returns bearish direction when MACD crosses below signal
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/macd_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/macd_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  114) Indicators::RsiIndicator#initialize initializes with series and config
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  115) Indicators::RsiIndicator#min_required_candles returns minimum candles required for RSI
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  116) Indicators::RsiIndicator#calculate_at returns hash with required keys
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  117) Indicators::RsiIndicator#calculate_at uses CandleSeries#rsi for calculation
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  118) Indicators::RsiIndicator#calculate_at returns bullish direction for oversold RSI
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  119) Indicators::RsiIndicator#calculate_at returns bearish direction for overbought RSI
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  120) Indicators::RsiIndicator#calculate_at returns nil for neutral RSI
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  121) Indicators::RsiIndicator#rsi_value_at returns raw RSI even in the neutral zone
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  122) Indicators::RsiIndicator#rsi_value_at returns nil when RSI cannot be computed
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/rsi_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/rsi_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  123) Indicators::SupertrendIndicator#initialize initializes with series and config
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  124) Indicators::SupertrendIndicator#initialize uses default config when not provided
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  125) Indicators::SupertrendIndicator#min_required_candles returns minimum candles required
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  126) Indicators::SupertrendIndicator#ready? returns false when not enough candles
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  127) Indicators::SupertrendIndicator#ready? returns true when enough candles
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  128) Indicators::SupertrendIndicator#calculate_at returns hash with required keys
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  129) Indicators::SupertrendIndicator#calculate_at returns direction as :bullish or :bearish
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  130) Indicators::SupertrendIndicator#calculate_at returns confidence between 0 and 100
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  131) Indicators::SupertrendIndicator#calculate_at calculates Supertrend once and caches result
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  132) Indicators::SupertrendIndicator#calculate_at with trading hours filter returns nil for candles outside trading hours
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `new'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:16:in `block (3 levels) in <top (required)>'
       # ./spec/services/indicators/supertrend_indicator_spec.rb:14:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  133) Indicators::TrendDurationIndicator#calculate_at with insufficient data returns nil when index is too small
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  134) Indicators::TrendDurationIndicator#calculate_at with sufficient data returns hash with required keys
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  135) Indicators::TrendDurationIndicator#calculate_at with sufficient data returns value hash with trend information
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  136) Indicators::TrendDurationIndicator#calculate_at with sufficient data returns direction as :bullish or :bearish
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  137) Indicators::TrendDurationIndicator#calculate_at with sufficient data returns confidence between 0 and 100
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  138) Indicators::TrendDurationIndicator#calculate_at with trading hours filter returns nil for candles outside trading hours
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:61:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  139) Indicators::TrendDurationIndicator HMA calculation calculates HMA values correctly
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:153:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:153:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:151:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  140) Indicators::TrendDurationIndicator trend detection with rising trend detects bullish trend
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:205:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:205:in `block (5 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:202:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  141) Indicators::TrendDurationIndicator trend detection with falling trend detects bearish trend
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:237:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:237:in `block (5 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:234:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  142) Indicators::TrendDurationIndicator trend duration tracking tracks trend duration
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:272:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:272:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:270:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  143) Indicators::TrendDurationIndicator trend duration tracking calculates probable duration
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:272:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:272:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:270:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  144) Indicators::TrendDurationIndicator edge cases handles nil values gracefully
       Failure/Error:
         def initialize(timestamp:, open:, high:, low:, close:, volume:)
           @timestamp = timestamp
           @open = open.to_f
           @high = high.to_f
           @low = low.to_f
           @close = close.to_f
           @volume = volume.to_i
         end

       ArgumentError:
         missing keyword: :timestamp
       # ./app/models/candle.rb:7:in `initialize'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:315:in `new'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:315:in `block (4 levels) in <top (required)>'
       # ./spec/services/indicators/trend_duration_indicator_spec.rb:313:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  145) Live::ExitEngine#normalize_exit_reason_with_final_pnl backfills meta when final PnL inputs are incomplete
       Failure/Error: expect(tracker.meta['exit_reason']).to eq('MANUAL_HALT')

         expected: "MANUAL_HALT"
              got: nil

         (compared using ==)
       # ./spec/services/live/exit_engine_spec.rb:456:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  146) Live::PnlUpdaterService#run_loop when market is closed and no active positions calls flush! at least once as required
       Failure/Error: expect(service).to have_received(:flush!).at_least(:once)

         (#<Live::PnlUpdaterService:0x00007f12d60629e0 @queue={}, @mutex=#<Monitor:0x00007f12d6073290>, @running=false, @thread=nil, @logger=#<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast">, @sleep_mutex=#<Thread::Mutex:0x00007f12d60731f0>, @sleep_cv=#<Thread::ConditionVariable:0x00007f12d6073178>, @last_heartbeat_at=nil, @last_positions_keepalive_at=nil>).flush!(*(any args))
             expected: at least 1 time with any arguments
             received: 0 times with any arguments
       # ./spec/services/live/pnl_updater_service_market_close_spec.rb:23:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  147) Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field round-trips pnl_pct as DECIMAL (0.30 stored → 0.30 fetched)
       Failure/Error: expect(result).not_to be_nil

         expected: not nil
              got: nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:58:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  148) Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field round-trips negative pnl_pct as DECIMAL (-0.12 stored → -0.12 fetched)
       Failure/Error: expect(result[:pnl_pct]).to be_within(0.0001).of(-0.12)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:66:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  149) Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field stores pnl_pct < 1.0 for a 30% gain (not 30.0)
       Failure/Error: expect(result[:pnl_pct]).to be < 1.0

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:73:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  150) Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field stores pnl_pct > -1.0 for a 12% loss (not -12.0)
       Failure/Error: expect(result[:pnl_pct]).to be > -1.0

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:80:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  151) Live::RedisPnlCache#store_pnl / #fetch_pnl — hwm_pnl_pct field round-trips hwm_pnl_pct as DECIMAL (0.45 → 0.45)
       Failure/Error: expect(result[:hwm_pnl_pct]).to be_within(0.0001).of(0.45)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:95:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  152) Live::RedisPnlCache#store_pnl / #fetch_pnl — price_change_pct field (PERCENTAGE format) stores price_change_pct as PERCENTAGE (30.0) when ltp is 130 and entry is 100
       Failure/Error: expect(result[:price_change_pct]).to be_within(0.01).of(30.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:113:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  153) Live::RedisPnlCache#store_pnl / #fetch_pnl — price_change_pct field (PERCENTAGE format) price_change_pct differs from pnl_pct by factor of 100 (different units)
       Failure/Error: ratio = result[:price_change_pct] / result[:pnl_pct]

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:124:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  154) Live::RedisPnlCache#store_pnl / #fetch_pnl — drawdown_pct field (PERCENTAGE format) stores drawdown_pct as PERCENTAGE when there is a drawdown from HWM
       Failure/Error: expect(result[:drawdown_pct]).to be_within(0.1).of(25.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:142:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  155) Live::RedisPnlCache#store_pnl / #fetch_pnl — drawdown_pct field (PERCENTAGE format) stores drawdown_rupees as absolute ₹
       Failure/Error: expect(result[:drawdown_rupees]).to be_within(0.01).of(750.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:153:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  156) Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips pnl as absolute ₹
       Failure/Error: expect(result[:pnl]).to be_within(0.01).of(2250.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:170:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  157) Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips ltp as absolute price
       Failure/Error: expect(result[:ltp]).to be_within(0.01).of(130.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:175:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  158) Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips hwm_pnl as absolute ₹
       Failure/Error: expect(result[:hwm_pnl]).to be_within(0.01).of(3000.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:180:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  159) Live::RedisPnlCache last-wins update semantics overwrites pnl_pct with the latest value
       Failure/Error: expect(result[:pnl_pct]).to be_within(0.0001).of(0.30)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:193:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  160) Live::RedisPnlCache last-wins update semantics reflects latest ltp after tick update
       Failure/Error: expect(result[:ltp]).to be_within(0.01).of(120.0)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/live/redis_pnl_cache_pct_spec.rb:201:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  161) Live::UnderlyingContextEvaluator#evaluate_underlying_context when BOS breaks against a long_ce position (bearish BOS) returns :exit with UNDERLYING_STRUCTURE_BREAK reason
       Failure/Error: expect(result[:action]).to eq(:exit)

         expected: :exit
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:exit
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:168:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  162) Live::UnderlyingContextEvaluator#evaluate_underlying_context when BOS breaks against a long_pe position (bullish BOS) returns :exit with UNDERLYING_STRUCTURE_BREAK reason
       Failure/Error: expect(result[:action]).to eq(:exit)

         expected: :exit
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:exit
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:204:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  163) Live::UnderlyingContextEvaluator#evaluate_underlying_context when trend is weak AND ATR is collapsing (dual weakness) returns :exit with UNDERLYING_DUAL_WEAKNESS reason
       Failure/Error: expect(result[:action]).to eq(:exit)

         expected: :exit
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:exit
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:214:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  164) Live::UnderlyingContextEvaluator#evaluate_underlying_context when trend is weak but ATR is healthy returns :tighten with configured multiplier (0.5)
       Failure/Error: expect(result[:action]).to eq(:tighten)

         expected: :tighten
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:tighten
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:224:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  165) Live::UnderlyingContextEvaluator#evaluate_underlying_context when ATR is collapsing but trend score is healthy returns :tighten with configured multiplier (0.5)
       Failure/Error: expect(result[:action]).to eq(:tighten)

         expected: :tighten
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:tighten
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:235:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  166) Live::UnderlyingContextEvaluator#evaluate_underlying_context when ActiveCache provides pos_data with position_direction uses pos_data.position_direction to detect BOS break correctly
       Failure/Error: expect(result[:action]).to eq(:exit)

         expected: :exit
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:exit
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:274:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  167) Live::UnderlyingContextEvaluator#evaluate_underlying_context with configurable thresholds uses the configured trend_score_threshold
       Failure/Error: expect(result[:action]).to eq(:tighten)

         expected: :tighten
              got: :hold

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:tighten
         +:hold

       # ./spec/services/live/underlying_context_evaluator_spec.rb:315:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  168) Live::UnifiedExitChecker.check_exit_conditions returns adaptive hard stop when loss exceeds entry guard floor
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/live/unified_exit_checker_spec.rb:45:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  169) Live::UnifiedExitChecker.check_exit_conditions returns adaptive trail exit when giveback exceeds stage floor
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/live/unified_exit_checker_spec.rb:56:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  170) Live::UnifiedExitChecker.check_exit_conditions returns nil when price remains above the trail floor
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/live/unified_exit_checker_spec.rb:67:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  171) Market::SessionResolver.current returns :opening between 09:15 and 10:30 IST
       Failure/Error:
         travel_to Time.zone.parse("2025-03-18 09:30:00 +0530") do
           expect(described_class.current).to eq(:opening)
         end

       NoMethodError:
         undefined method `travel_to' for #<RSpec::ExampleGroups::MarketSessionResolver::Current:0x00007f12d4f78b20>
       # ./spec/services/market/session_resolver_spec.rb:8:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  172) Market::SessionResolver.current returns :gamma between 14:00 and 15:15 IST
       Failure/Error:
         travel_to Time.zone.parse("2025-03-18 14:30:00 +0530") do
           expect(described_class.current).to eq(:gamma)
         end

       NoMethodError:
         undefined method `travel_to' for #<RSpec::ExampleGroups::MarketSessionResolver::Current:0x00007f12c7ae2f00>
       # ./spec/services/market/session_resolver_spec.rb:14:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  173) Market::SessionResolver.current returns :midday between 10:30 and 14:00 IST
       Failure/Error:
         travel_to Time.zone.parse("2025-03-18 12:00:00 +0530") do
           expect(described_class.current).to eq(:midday)
         end

       NoMethodError:
         undefined method `travel_to' for #<RSpec::ExampleGroups::MarketSessionResolver::Current:0x00007f12c65e3ca8>
       # ./spec/services/market/session_resolver_spec.rb:20:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  174) Options::StrikeQualification::ExpectedMoveValidator#call blocks NIFTY when expected premium is too low
       Failure/Error: expect(result[:ok]).to be(false)

         expected false
              got true
       # ./spec/services/options/strike_qualification/expected_move_validator_spec.rb:18:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  175) Options::StrikeQualification::ExpectedMoveValidator#call blocks NIFTY full_deploy for ATM±1 when expectancy is insufficient
       Failure/Error: expect(result[:ok]).to be(false)

         expected false
              got true
       # ./spec/services/options/strike_qualification/expected_move_validator_spec.rb:45:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  176) Options::StrikeQualification::StrikeSelector#call selects ATM+1 for NIFTY bullish CE
       Failure/Error: expect(result[:atm_strike]).to eq(25_000)

         expected: 25000
              got: 25050

         (compared using ==)
       # ./spec/services/options/strike_qualification/strike_selector_spec.rb:50:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  177) Options::StrikeQualification::StrikeSelector#call selects ATM-1 for NIFTY bearish PE
       Failure/Error: expect(result[:atm_strike]).to eq(25_000)

         expected: 25000
              got: 25050

         (compared using ==)
       # ./spec/services/options/strike_qualification/strike_selector_spec.rb:66:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  178) Options::StrikeQualification::StrikeSelector#call forces ATM in chop context
       Failure/Error: expect(result[:strike]).to eq(25_000)

         expected: 25000
              got: 25050

         (compared using ==)
       # ./spec/services/options/strike_qualification/strike_selector_spec.rb:82:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  179) Options::StrikeQualification::StrikeSelector#call forces ATM when permission is execution_only
       Failure/Error: expect(result[:strike]).to eq(25_000)

         expected: 25000
              got: 25050

         (compared using ==)
       # ./spec/services/options/strike_qualification/strike_selector_spec.rb:97:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  180) Options::StrikeSelector.strike_type_for_momentum returns :itm for moderate momentum (score 2/3)
       Failure/Error: expect(described_class.strike_type_for_momentum(2)).to eq(:itm)

         expected: :itm
              got: :atm

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:itm
         +:atm

       # ./spec/services/options/strike_selector_simple_spec.rb:12:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  181) Options::StrikeSelector.strike_type_for_momentum returns :skip for weak momentum (score 1/3)
       Failure/Error: expect(described_class.strike_type_for_momentum(1)).to eq(:skip)

         expected: :skip
              got: :atm

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:skip
         +:atm

       # ./spec/services/options/strike_selector_simple_spec.rb:16:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  182) Options::StrikeSelector#strike_type returns :itm for momentum > 0.4
       Failure/Error: expect(selector.strike_type).to eq(:itm)

         expected: :itm
              got: :atm

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:itm
         +:atm

       # ./spec/services/options/strike_selector_simple_spec.rb:32:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  183) Options::StrikeSelector#strike_type returns :skip for momentum <= 0.4
       Failure/Error: expect(selector.strike_type).to eq(:skip)

         expected: :skip
              got: :atm

         (compared using ==)

         Diff:
         @@ -1 +1 @@
         -:skip
         +:atm

       # ./spec/services/options/strike_selector_simple_spec.rb:37:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  184) Options::StrikeSelector#select with valid candidates returns normalized instrument hash
       Failure/Error: expect(result).to be_a(Hash)
         expected nil to be a kind of Hash
       # ./spec/services/options/strike_selector_spec.rb:72:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  185) Options::StrikeSelector#select with valid candidates includes required fields in normalized hash
       Failure/Error: expect(result[:ltp]).to eq(150.5)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/options/strike_selector_spec.rb:81:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  186) Options::StrikeSelector#select with valid candidates includes OTM depth information
       Failure/Error: expect(result[:otm_depth]).to be_a(Integer)

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/services/options/strike_selector_spec.rb:89:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  187) Options::StrikeSelector#select with trend score determining OTM depth allows only ATM when trend_score is low
       Failure/Error: expect(result).not_to be_nil

         expected: not nil
              got: nil
       # ./spec/services/options/strike_selector_spec.rb:156:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  188) Options::StrikeSelector#select with trend score determining OTM depth allows 1OTM when trend_score >= 12
       Failure/Error: expect(result).not_to be_nil

         expected: not nil
              got: nil
       # ./spec/services/options/strike_selector_spec.rb:168:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  189) Options::StrikeSelector#select with trend score determining OTM depth allows 2OTM when trend_score >= 18
       Failure/Error: expect(result).not_to be_nil

         expected: not nil
              got: nil
       # ./spec/services/options/strike_selector_spec.rb:181:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  190) Options::StrikeSelector#select when no candidates from analyzer returns nil
       Failure/Error: atm_strike = rules.atm(spot)

         #<InstanceDouble(Options::IndexRules::Nifty) (anonymous)> received :atm with unexpected arguments
           expected: (25000.0)
                got: (22150.75)
          Please stub a default value first if message might be received with other args as well.
       # ./app/services/options/strike_selector.rb:59:in `select'
       # ./spec/services/options/strike_selector_spec.rb:193:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  191) Options::StrikeSelector#select when candidate fails index rules returns nil
       Failure/Error: atm_strike = rules.atm(spot)

         #<InstanceDouble(Options::IndexRules::Nifty) (anonymous)> received :atm with unexpected arguments
           expected: (25000.0)
                got: (22150.75)
          Please stub a default value first if message might be received with other args as well.
       # ./app/services/options/strike_selector.rb:59:in `select'
       # ./spec/services/options/strike_selector_spec.rb:219:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  192) Options::StrikeSelector#select with bearish direction (PE options) selects PE strikes below ATM
       Failure/Error: expect(result).not_to be_nil

         expected: not nil
              got: nil
       # ./spec/services/options/strike_selector_spec.rb:286:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  193) Orders::GammaTrailingEngine#call State 1: Early trade (profit < 10%) returns 12% SL from entry
       Failure/Error: cached = fetch(tracker.id)[:highest_price]
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :id with (no args)
       # ./app/services/live/position_runtime_cache.rb:83:in `highest_price_for'
       # ./app/services/live/position_runtime_cache.rb:90:in `update_highest_price!'
       # ./app/services/orders/gamma_trailing_engine.rb:89:in `update_highest'
       # ./app/services/orders/gamma_trailing_engine.rb:35:in `call'
       # ./spec/services/orders/gamma_trailing_engine_spec.rb:16:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  194) Orders::GammaTrailingEngine#call State 2: Trend confirmed returns 20% trailing gap from peak (normal trail)
       Failure/Error: cached = fetch(tracker.id)[:highest_price]
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :id with (no args)
       # ./app/services/live/position_runtime_cache.rb:83:in `highest_price_for'
       # ./app/services/live/position_runtime_cache.rb:90:in `update_highest_price!'
       # ./app/services/orders/gamma_trailing_engine.rb:89:in `update_highest'
       # ./app/services/orders/gamma_trailing_engine.rb:35:in `call'
       # ./spec/services/orders/gamma_trailing_engine_spec.rb:27:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  195) Orders::GammaTrailingEngine#call State 3: Gamma expansion loosens trailing to 35% gap (trail_gamma)
       Failure/Error: cached = fetch(tracker.id)[:highest_price]
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :id with (no args)
       # ./app/services/live/position_runtime_cache.rb:83:in `highest_price_for'
       # ./app/services/live/position_runtime_cache.rb:90:in `update_highest_price!'
       # ./app/services/orders/gamma_trailing_engine.rb:89:in `update_highest'
       # ./app/services/orders/gamma_trailing_engine.rb:35:in `call'
       # ./spec/services/orders/gamma_trailing_engine_spec.rb:41:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  196) Orders::GammaTrailingEngine#call State 4: Exhaustion tightens trailing to 10% gap (trail_exhaust)
       Failure/Error: cached = fetch(tracker.id)[:highest_price]
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :id with (no args)
       # ./app/services/live/position_runtime_cache.rb:83:in `highest_price_for'
       # ./app/services/live/position_runtime_cache.rb:90:in `update_highest_price!'
       # ./app/services/orders/gamma_trailing_engine.rb:89:in `update_highest'
       # ./app/services/orders/gamma_trailing_engine.rb:35:in `call'
       # ./spec/services/orders/gamma_trailing_engine_spec.rb:53:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  197) Orders::GatewayLive#exit_market generates client order ID when not provided
       Failure/Error: expect(args[:client_order_id]).to match(/^AS-EXIT-#{tracker.security_id}-\d+-[a-f0-9]{4}$/)

         expected "SCALPER_EXIT_55111_19c21237" to match /^AS-EXIT-55111-\d+-[a-f0-9]{4}$/
         Diff:
         @@ -1 +1 @@
         -/^AS-EXIT-55111-\d+-[a-f0-9]{4}$/
         +"SCALPER_EXIT_55111_19c21237"

       # ./spec/services/orders/gateway_live_spec.rb:53:in `block (4 levels) in <top (required)>'
       # ./spec/services/orders/gateway_live_spec.rb:52:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  198) Orders::GatewayLive#place_market with buy side calls Placer.buy_market! with correct parameters
       Failure/Error:
         expect(Orders::Placer).to have_received(:buy_market!).with(
           seg: 'NSE_FNO',
           sid: '55111',
           qty: 50,
           client_order_id: match(/^AS-buy-55111-\d+-[a-f0-9]{4}$/),
           price: 100.5,
           target_price: nil,
           stop_loss_price: nil,
           product_type: 'INTRADAY'
         )

         #<Orders::Placer (class)> received :buy_market! with unexpected arguments
           expected: ({:client_order_id=>match /^AS-buy-55111-\d+-[a-f0-9]{4}$/, :price=>100.5, :product_type=>"INTRADAY", :qty=>50, :seg=>"NSE_FNO", :sid=>"55111", :stop_loss_price=>nil, :target_price=>nil}) (options hash)
                got: ({:client_order_id=>"SCALPER_buy_55111_430b0a55", :price=>100.5, :product_type=>"INTRADAY", :qty=>50, :seg=>"NSE_FNO", :sid=>"55111", :stop_loss_price=>nil, :target_price=>nil}) (keyword arguments)
         Diff:
         @@ -1,4 +1,4 @@
         -[{:client_order_id=>match /^AS-buy-55111-\d+-[a-f0-9]{4}$/,
         +[{:client_order_id=>"SCALPER_buy_55111_430b0a55",
            :price=>100.5,
            :product_type=>"INTRADAY",
            :qty=>50,

       # ./spec/services/orders/gateway_live_spec.rb:93:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  199) Orders::GatewayLive#place_market with sell side calls Placer.sell_market! with correct parameters
       Failure/Error:
         expect(Orders::Placer).to have_received(:sell_market!).with(
           seg: 'NSE_FNO',
           sid: '55111',
           qty: 50,
           client_order_id: match(/^AS-sell-55111-\d+-[a-f0-9]{4}$/),
           product_type: 'INTRADAY'
         )

         #<Orders::Placer (class)> received :sell_market! with unexpected arguments
           expected: ({:client_order_id=>match /^AS-sell-55111-\d+-[a-f0-9]{4}$/, :product_type=>"INTRADAY", :qty=>50, :seg=>"NSE_FNO", :sid=>"55111"}) (options hash)
                got: ({:client_order_id=>"SCALPER_sell_55111_2f742e53", :product_type=>"INTRADAY", :qty=>50, :seg=>"NSE_FNO", :sid=>"55111"}) (keyword arguments)
         Diff:
         @@ -1,4 +1,4 @@
         -[{:client_order_id=>match /^AS-sell-55111-\d+-[a-f0-9]{4}$/,
         +[{:client_order_id=>"SCALPER_sell_55111_2f742e53",
            :product_type=>"INTRADAY",
            :qty=>50,
            :seg=>"NSE_FNO",

       # ./spec/services/orders/gateway_live_spec.rb:150:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  200) Orders::GatewayLive#generate_client_order_id generates unique IDs with random component
       Failure/Error: expect(id1).to match(/^AS-buy-55111-\d+-[a-f0-9]{4}$/)

         expected "SCALPER_buy_55111_69345bf6" to match /^AS-buy-55111-\d+-[a-f0-9]{4}$/
         Diff:
         @@ -1 +1 @@
         -/^AS-buy-55111-\d+-[a-f0-9]{4}$/
         +"SCALPER_buy_55111_69345bf6"

       # ./spec/services/orders/gateway_live_spec.rb:326:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  201) Orders::GatewayLive#generate_client_order_id includes prefix and security_id in ID
       Failure/Error: expect(id).to include('AS-sell-55112')
         expected "SCALPER_sell_55112_fa5d0907" to include "AS-sell-55112"
       # ./spec/services/orders/gateway_live_spec.rb:334:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  202) Orders::GatewayPaper#wallet_snapshot returns unified wallet keys with configured balance when no positions
       Failure/Error:
         expect(result).to eq(
           cash: 100_000,
           equity: 100_000,
           mtm: 0,
           exposure: 0,
           utilized: 0,
           margin: 0
         )

         expected: {:cash=>100000, :equity=>100000, :exposure=>0, :margin=>0, :mtm=>0, :utilized=>0}
              got: {:cash=>100000.0, :equity=>100000.0, :exposure=>0.0, :margin=>0, :mtm=>0, :source=>"legacy", :utilized=>0.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 100000,
         -:equity => 100000,
         -:exposure => 0,
         +:cash => 100000.0,
         +:equity => 100000.0,
         +:exposure => 0.0,
          :margin => 0,
          :mtm => 0,
         -:utilized => 0,
         +:source => "legacy",
         +:utilized => 0.0,

       # ./spec/services/orders/gateway_paper_spec.rb:172:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  203) Orders::GatewayPaper#wallet_snapshot adds cumulative realized PnL from paper exits on prior days
       Failure/Error:
         expect(result).to eq(
           cash: 105_000,
           equity: 105_000,
           mtm: 0,
           exposure: 0,
           utilized: 0,
           margin: 0
         )

         expected: {:cash=>105000, :equity=>105000, :exposure=>0, :margin=>0, :mtm=>0, :utilized=>0}
              got: {:cash=>105000.0, :equity=>105000.0, :exposure=>0.0, :margin=>0, :mtm=>0, :source=>"legacy", :utilized=>0.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 105000,
         -:equity => 105000,
         -:exposure => 0,
         +:cash => 105000.0,
         +:equity => 105000.0,
         +:exposure => 0.0,
          :margin => 0,
          :mtm => 0,
         -:utilized => 0,
         +:source => "legacy",
         +:utilized => 0.0,

       # ./spec/services/orders/gateway_paper_spec.rb:191:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  204) Orders::GatewayPaper#wallet_snapshot reduces cash and sets exposure to deployed premium for active paper legs
       Failure/Error:
         expect(result).to eq(
           cash: 95_000,
           equity: 100_200,
           mtm: 200,
           exposure: 5_000,
           utilized: 5_000,
           margin: 0
         )

         expected: {:cash=>95000, :equity=>100200, :exposure=>5000, :margin=>0, :mtm=>200, :utilized=>5000}
              got: {:cash=>95000.0, :equity=>100200.0, :exposure=>5000.0, :margin=>0, :mtm=>200.0, :source=>"legacy", :utilized=>5000.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 95000,
         -:equity => 100200,
         -:exposure => 5000,
         +:cash => 95000.0,
         +:equity => 100200.0,
         +:exposure => 5000.0,
          :margin => 0,
         -:mtm => 200,
         -:utilized => 5000,
         +:mtm => 200.0,
         +:source => "legacy",
         +:utilized => 5000.0,

       # ./spec/services/orders/gateway_paper_spec.rb:212:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  205) Orders::GatewayPaper#wallet_snapshot clamps cash at zero when base plus realized is below deployed
       Failure/Error:
         expect(result).to eq(
           cash: 0,
           equity: 200_000,
           mtm: 0,
           exposure: 200_000,
           utilized: 200_000,
           margin: 0
         )

         expected: {:cash=>0, :equity=>200000, :exposure=>200000, :margin=>0, :mtm=>0, :utilized=>200000}
              got: {:cash=>0.0, :equity=>200000.0, :exposure=>200000.0, :margin=>0, :mtm=>0.0, :source=>"legacy", :utilized=>200000.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 0,
         -:equity => 200000,
         -:exposure => 200000,
         +:cash => 0.0,
         +:equity => 200000.0,
         +:exposure => 200000.0,
          :margin => 0,
         -:mtm => 0,
         -:utilized => 200000,
         +:mtm => 0.0,
         +:source => "legacy",
         +:utilized => 200000.0,

       # ./spec/services/orders/gateway_paper_spec.rb:281:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  206) Orders::GatewayPaper#wallet_snapshot uses default balance when not configured
       Failure/Error:
         expect(result).to eq(
           cash: 100_000,
           equity: 100_000,
           mtm: 0,
           exposure: 0,
           utilized: 0,
           margin: 0
         )

         expected: {:cash=>100000, :equity=>100000, :exposure=>0, :margin=>0, :mtm=>0, :utilized=>0}
              got: {:cash=>100000.0, :equity=>100000.0, :exposure=>0.0, :margin=>0, :mtm=>0, :source=>"legacy", :utilized=>0.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 100000,
         -:equity => 100000,
         -:exposure => 0,
         +:cash => 100000.0,
         +:equity => 100000.0,
         +:exposure => 0.0,
          :margin => 0,
          :mtm => 0,
         -:utilized => 0,
         +:source => "legacy",
         +:utilized => 0.0,

       # ./spec/services/orders/gateway_paper_spec.rb:296:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  207) Orders::GatewayPaper#wallet_snapshot when realized_scope is daily ignores exits before today for realized cash
       Failure/Error:
         expect(result).to eq(
           cash: 100_000,
           equity: 100_000,
           mtm: 0,
           exposure: 0,
           utilized: 0,
           margin: 0
         )

         expected: {:cash=>100000, :equity=>100000, :exposure=>0, :margin=>0, :mtm=>0, :utilized=>0}
              got: {:cash=>100000.0, :equity=>100000.0, :exposure=>0.0, :margin=>0, :mtm=>0, :source=>"legacy", :utilized=>0.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 100000,
         -:equity => 100000,
         -:exposure => 0,
         +:cash => 100000.0,
         +:equity => 100000.0,
         +:exposure => 0.0,
          :margin => 0,
          :mtm => 0,
         -:utilized => 0,
         +:source => "legacy",
         +:utilized => 0.0,

       # ./spec/services/orders/gateway_paper_spec.rb:238:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  208) Orders::GatewayPaper#wallet_snapshot when realized_scope is daily includes exits that exited today
       Failure/Error:
         expect(result).to eq(
           cash: 103_000,
           equity: 103_000,
           mtm: 0,
           exposure: 0,
           utilized: 0,
           margin: 0
         )

         expected: {:cash=>103000, :equity=>103000, :exposure=>0, :margin=>0, :mtm=>0, :utilized=>0}
              got: {:cash=>103000.0, :equity=>103000.0, :exposure=>0.0, :margin=>0, :mtm=>0, :source=>"legacy", :utilized=>0.0}

         (compared using ==)

         Diff:

         @@ -1,6 +1,7 @@
         -:cash => 103000,
         -:equity => 103000,
         -:exposure => 0,
         +:cash => 103000.0,
         +:equity => 103000.0,
         +:exposure => 0.0,
          :margin => 0,
          :mtm => 0,
         -:utilized => 0,
         +:source => "legacy",
         +:utilized => 0.0,

       # ./spec/services/orders/gateway_paper_spec.rb:257:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  209) Orders::MfeExitEngine#call with NIFTY (retrace_ratio 0.35) returns stop based on MFE retrace
       Failure/Error:
         @position.update!(
           highest_price: @highest,
           lowest_price: lowest,
           meta: meta
         )

         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :update! with ({:highest_price=>300.0, :lowest_price=>100.0, :meta=>{}})
       # ./app/services/orders/mfe_exit_engine.rb:73:in `update_extremes'
       # ./app/services/orders/mfe_exit_engine.rb:24:in `call'
       # ./spec/services/orders/mfe_exit_engine_spec.rb:22:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  210) Orders::MfeExitEngine#call with SENSEX (retrace_ratio 0.45) returns stop based on MFE retrace
       Failure/Error:
         @position.update!(
           highest_price: @highest,
           lowest_price: lowest,
           meta: meta
         )

         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :update! with ({:highest_price=>300.0, :lowest_price=>100.0, :meta=>{}})
       # ./app/services/orders/mfe_exit_engine.rb:73:in `update_extremes'
       # ./app/services/orders/mfe_exit_engine.rb:24:in `call'
       # ./spec/services/orders/mfe_exit_engine_spec.rb:38:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  211) Percentage format consistency across the trading pipeline Live::UnifiedExitChecker entry guard hard stop at -30% does NOT exit at -29.9%
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/pct_consistency_spec.rb:141:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  212) Percentage format consistency across the trading pipeline Live::UnifiedExitChecker entry guard hard stop at -30% exits at exactly -30%
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/pct_consistency_spec.rb:147:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  213) Percentage format consistency across the trading pipeline Live::UnifiedExitChecker adaptive trail giveback exit exits when runner-mode floor is breached
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/pct_consistency_spec.rb:165:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  214) Percentage format consistency across the trading pipeline Live::UnifiedExitChecker pnl_pct returned in result returns pnl_pct as PERCENTAGE (multiplied by 100) for UI display
       Failure/Error: elapsed  = (Time.current - tracker.created_at).to_f
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :created_at with (no args)
       # ./app/services/risk/rules/zero_hwm_false_entry_rule.rb:29:in `evaluate'
       # ./app/services/risk/rules/rule_engine.rb:43:in `block in evaluate'
       # ./app/services/risk/rules/rule_engine.rb:39:in `each'
       # ./app/services/risk/rules/rule_engine.rb:39:in `evaluate'
       # ./app/services/live/unified_exit_checker.rb:34:in `check_exit_conditions'
       # ./spec/services/pct_consistency_spec.rb:174:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  215) Portfolio::DrawdownGuard.trigger_global_exit! when not yet triggered with active positions exits all active positions with PORTFOLIO_FLOOR_BREACH reason
       Failure/Error: exit_engine.execute_exit(tracker, 'PORTFOLIO_FLOOR_BREACH')
         #<InstanceDouble(Live::ExitEngine) (anonymous)> was originally created in one example but has leaked into another example and can no longer be used. rspec-mocks' doubles are designed to only last for one example, and you need to create a new one in each example you wish to use it for.
       # ./app/services/portfolio/drawdown_guard.rb:111:in `block in exit_all_positions!'
       # ./app/services/portfolio/drawdown_guard.rb:105:in `each'
       # ./app/services/portfolio/drawdown_guard.rb:105:in `exit_all_positions!'
       # ./app/services/portfolio/drawdown_guard.rb:40:in `trigger_global_exit!'
       # ./spec/services/portfolio/drawdown_guard_spec.rb:81:in `block (5 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  216) Portfolio::PnlTracker.mark_realized increments the REALIZED key by the pnl amount
       Failure/Error: added = r.sadd(KEY_REALIZED_TRACKERS, tracker_id.to_s)
         #<InstanceDouble(Redis) (anonymous)> received unexpected message :sadd with ("portfolio:pnl:realized_trackers", "99")
       # ./app/services/portfolio/pnl_tracker.rb:56:in `mark_realized'
       # ./spec/services/portfolio/pnl_tracker_spec.rb:54:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  217) Portfolio::PnlTracker.mark_realized removes the tracker from the UNREALIZED hash
       Failure/Error: added = r.sadd(KEY_REALIZED_TRACKERS, tracker_id.to_s)
         #<InstanceDouble(Redis) (anonymous)> received unexpected message :sadd with ("portfolio:pnl:realized_trackers", "99")
       # ./app/services/portfolio/pnl_tracker.rb:56:in `mark_realized'
       # ./spec/services/portfolio/pnl_tracker_spec.rb:59:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  218) Portfolio::PnlTracker.mark_realized handles negative pnl (losses) correctly
       Failure/Error: added = r.sadd(KEY_REALIZED_TRACKERS, tracker_id.to_s)
         #<InstanceDouble(Redis) (anonymous)> received unexpected message :sadd with ("portfolio:pnl:realized_trackers", "7")
       # ./app/services/portfolio/pnl_tracker.rb:56:in `mark_realized'
       # ./spec/services/portfolio/pnl_tracker_spec.rb:64:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  219) Portfolio::ProfitLockEngine.evaluate! when net PnL drops below the locked floor returns true and triggers the guard
       Failure/Error:
         expect(Portfolio::DrawdownGuard).to receive(:trigger_global_exit!).with(
           net_pnl: 5_500.0,
           floor: 6_000.0,
           level: 1
         )

         #<Portfolio::DrawdownGuard (class)> received :trigger_global_exit! with unexpected arguments
           expected: ({:floor=>6000.0, :level=>1, :net_pnl=>5500.0}) (keyword arguments)
                got: ({:floor=>6000.0, :level=>0, :net_pnl=>5500.0}) (options hash)
         Diff:
         @@ -1 +1 @@
         -[{:floor=>6000.0, :level=>1, :net_pnl=>5500.0}]
         +[{:floor=>6000.0, :level=>0, :net_pnl=>5500.0}]

       # ./spec/services/portfolio/profit_lock_engine_spec.rb:131:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  220) Positions::ActiveCache subscribes option instruments and emits notifications when adding a position
       Failure/Error: meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :meta with (no args)
       # ./app/services/positions/metadata_resolver.rb:8:in `index_key'
       # ./app/services/positions/active_cache.rb:195:in `add_position'
       # ./spec/services/positions/activecache_add_remove_spec.rb:44:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  221) Positions::ActiveCache unsubscribes option instruments and emits notifications when removing a position
       Failure/Error: meta = tracker.meta.is_a?(Hash) ? tracker.meta : {}
         #<InstanceDouble(PositionTracker) (anonymous)> received unexpected message :meta with (no args)
       # ./app/services/positions/metadata_resolver.rb:8:in `index_key'
       # ./app/services/positions/active_cache.rb:195:in `add_position'
       # ./spec/services/positions/activecache_add_remove_spec.rb:53:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  222) Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts RSI per timeframe from the nested indicators path
       Failure/Error: expect(metadata[:mtf_rsi]).to eq({ m5: 62.1, m15: 58.4, m60: 55.0 })

         expected: {:m15=>58.4, :m5=>62.1, :m60=>55.0}
              got: {:indicators=>nil, :meta=>nil}

         (compared using ==)

         Diff:
         @@ -1,3 +1,2 @@
         -:m15 => 58.4,
         -:m5 => 62.1,
         -:m60 => 55.0,
         +:indicators => nil,
         +:meta => nil,

       # ./spec/services/signal/metadata_builder_spec.rb:52:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  223) Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts MACD per timeframe from the nested indicators path
       Failure/Error:
         expect(metadata[:mtf_macd]).to eq({
                                             m5:  { macd: 1.2, signal: 0.8, hist: 0.4 },
                                             m15: { macd: 0.9, signal: 0.7, hist: 0.2 },
                                             m60: { macd: 0.5, signal: 0.3, hist: 0.2 }
                                           })

         expected: {:m15=>{:hist=>0.2, :macd=>0.9, :signal=>0.7}, :m5=>{:hist=>0.4, :macd=>1.2, :signal=>0.8}, :m60=>{:hist=>0.2, :macd=>0.5, :signal=>0.3}}
              got: {:indicators=>nil, :meta=>nil}

         (compared using ==)

         Diff:
         @@ -1,3 +1,2 @@
         -:m15 => {:hist=>0.2, :macd=>0.9, :signal=>0.7},
         -:m5 => {:hist=>0.4, :macd=>1.2, :signal=>0.8},
         -:m60 => {:hist=>0.2, :macd=>0.5, :signal=>0.3},
         +:indicators => nil,
         +:meta => nil,

       # ./spec/services/signal/metadata_builder_spec.rb:56:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  224) Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts ATR per timeframe from the nested indicators path
       Failure/Error: expect(metadata[:mtf_atr]).to eq({ m5: 45.0, m15: 52.0, m60: 60.0 })

         expected: {:m15=>52.0, :m5=>45.0, :m60=>60.0}
              got: {:indicators=>nil, :meta=>nil}

         (compared using ==)

         Diff:
         @@ -1,3 +1,2 @@
         -:m15 => 52.0,
         -:m5 => 45.0,
         -:m60 => 60.0,
         +:indicators => nil,
         +:meta => nil,

       # ./spec/services/signal/metadata_builder_spec.rb:64:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  225) Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data does not produce the meta/indicators wrapper as the value
       Failure/Error: expect(metadata[:mtf_rsi]).not_to eq({ meta: nil, indicators: nil })

         expected: value != {:indicators=>nil, :meta=>nil}
              got: {:indicators=>nil, :meta=>nil}

         (compared using ==)

         Diff:
           <The diff is empty, are your objects producing identical `#inspect` output?>
       # ./spec/services/signal/metadata_builder_spec.rb:68:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  226) Signal::MomentumValidator.validate_option_pick rejects when premium expansion is below threshold
       Failure/Error: expect(result[:confirms]).to be false

         expected false
              got true
       # ./spec/services/signal/momentum_validator_spec.rb:46:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  227) Trading::AdminActions.buy_derivative! finds derivative and calls buy_option! with resolved index config
       Failure/Error:
         expect(derivative).to receive(:buy_option!).with(
           qty: 50,
           product_type: 'INTRADAY',
           index_cfg: index_cfg,
           meta: {}
         )

         #<Derivative id: 87, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:59:08.330562000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 844, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: 0.5e-1, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:59:08.330562000 +0530"> received :buy_option! with unexpected arguments
           expected: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"INTRADAY", :qty=>50}) (keyword arguments)
                got: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"NORMAL", :qty=>50}) (options hash)
         Diff:
         @@ -1,4 +1,4 @@
          [{:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"},
            :meta=>{},
         -  :product_type=>"INTRADAY",
         +  :product_type=>"NORMAL",
            :qty=>50}]

       # ./spec/services/trading/admin_actions_spec.rb:22:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  228) Trading::AdminActions.buy_derivative! prefers override index_key when provided
       Failure/Error:
         expect(derivative).to receive(:buy_option!).with(
           qty: nil,
           product_type: 'INTRADAY',
           index_cfg: banknifty_cfg,
           meta: { foo: 'bar' }
         )

         #<Derivative id: 88, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:59:08.374860000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 845, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: 0.5e-1, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:59:08.374860000 +0530"> received :buy_option! with unexpected arguments
           expected: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"BANKNIFTY", :segment=>"IDX_I"}, :meta=>{:foo=>"bar"}, :product_type=>"INTRADAY", :qty=>nil}) (keyword arguments)
                got: ({:index_cfg=>nil, :meta=>{:foo=>"bar"}, :product_type=>"NORMAL", :qty=>nil}) (options hash)
         Diff:
         @@ -1,4 +1 @@
         -[{:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"BANKNIFTY", :segment=>"IDX_I"},
         -  :meta=>{:foo=>"bar"},
         -  :product_type=>"INTRADAY",
         -  :qty=>nil}]
         +[{:index_cfg=>nil, :meta=>{:foo=>"bar"}, :product_type=>"NORMAL", :qty=>nil}]

       # ./spec/services/trading/admin_actions_spec.rb:37:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  229) Trading::AdminActions.buy_derivative! uses underlying_symbol to find index config when no override
       Failure/Error:
         expect(derivative).to receive(:buy_option!).with(
           qty: nil,
           product_type: 'INTRADAY',
           index_cfg: index_cfg,
           meta: {}
         )

         #<Derivative id: 89, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:59:08.409553000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 846, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: 0.5e-1, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:59:08.409553000 +0530"> received :buy_option! with unexpected arguments
           expected: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"INTRADAY", :qty=>nil}) (keyword arguments)
                got: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"NORMAL", :qty=>nil}) (options hash)
         Diff:
         @@ -1,4 +1,4 @@
          [{:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"},
            :meta=>{},
         -  :product_type=>"INTRADAY",
         +  :product_type=>"NORMAL",
            :qty=>nil}]

       # ./spec/services/trading/admin_actions_spec.rb:55:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  230) Trading::AdminActions.buy_derivative! falls back to symbol_name when underlying_symbol is missing
       Failure/Error:
         derivative.buy_option!(
           qty: qty,
           product_type: product_type,
           index_cfg: find_index_config(derivative: derivative, override_key: index_key),
           meta: meta
         )

         #<Derivative id: 91, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:59:08.466317000 +0530", display_name: "BANKNIFTY 56000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 847, instrument_type: "OPTION", isin: "INE987654321", lot_size: 15, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60002", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.56e5, symbol_name: "BANKNIFTY", tick_size: 0.5e-1, underlying_security_id: "25", underlying_symbol: "BANKNIFTY", updated_at: "2026-06-24 20:59:08.466317000 +0530"> received :buy_option! with unexpected arguments
           expected: ({:index_cfg=>{:key=>"BANKNIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"INTRADAY", :qty=>nil})
                got: ({:index_cfg=>nil, :meta=>{}, :product_type=>"NORMAL", :qty=>nil})
         Diff:
         @@ -1,4 +1 @@
         -[{:index_cfg=>{:key=>"BANKNIFTY", :segment=>"IDX_I"},
         -  :meta=>{},
         -  :product_type=>"INTRADAY",
         -  :qty=>nil}]
         +[{:index_cfg=>nil, :meta=>{}, :product_type=>"NORMAL", :qty=>nil}]

       # ./app/services/trading/admin_actions.rb:18:in `buy_derivative!'
       # ./spec/services/trading/admin_actions_spec.rb:79:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  231) Trading::AdminActions.buy_derivative! passes nil index_cfg when lookup fails
       Failure/Error:
         expect(derivative).to receive(:buy_option!).with(
           qty: nil,
           product_type: 'INTRADAY',
           index_cfg: nil,
           meta: {}
         )

         #<Derivative id: 92, asm_gsm_category: "NORMAL", asm_gsm_flag: "f", bracket_flag: "f", buy_bo_min_margin_per: 0.15e2, buy_bo_profit_range_max_perc: 0.3e2, buy_bo_profit_range_min_perc: 0.2e1, buy_bo_sl_range_max_perc: 0.25e2, buy_bo_sl_range_min_perc: 0.3e1, buy_co_min_margin_per: 0.1e2, buy_co_sl_range_max_perc: 0.2e2, buy_co_sl_range_min_perc: 0.5e1, buy_sell_indicator: "BOTH", cover_flag: "f", created_at: "2026-06-24 20:59:08.503768000 +0530", display_name: "NIFTY 25000 CE", exchange: "nse", expiry_date: "2026-07-24", expiry_flag: "f", instrument_code: "futures_index", instrument_id: 848, instrument_type: "OPTION", isin: "INE987654321", lot_size: 25, mtf_leverage: 0.1e1, option_type: "CE", security_id: "60001", segment: "derivatives", sell_bo_min_margin_per: 0.15e2, sell_bo_profit_range_max_perc: 0.3e2, sell_bo_profit_range_min_perc: 0.2e1, sell_bo_sl_min_range: 0.3e1, sell_bo_sl_range_max_perc: 0.25e2, sell_co_min_margin_per: 0.1e2, sell_co_sl_range_max_perc: 0.2e2, sell_co_sl_range_min_perc: 0.5e1, series: "EQ", strike_price: 0.25e5, symbol_name: "NIFTY", tick_size: 0.5e-1, underlying_security_id: "13", underlying_symbol: "NIFTY", updated_at: "2026-06-24 20:59:08.503768000 +0530"> received :buy_option! with unexpected arguments
           expected: ({:index_cfg=>nil, :meta=>{}, :product_type=>"INTRADAY", :qty=>nil}) (keyword arguments)
                got: ({:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"}, :meta=>{}, :product_type=>"NORMAL", :qty=>nil}) (options hash)
         Diff:
         @@ -1 +1,4 @@
         -[{:index_cfg=>nil, :meta=>{}, :product_type=>"INTRADAY", :qty=>nil}]
         +[{:index_cfg=>{:capital_alloc_pct=>0.3, :key=>"NIFTY", :segment=>"IDX_I"},
         +  :meta=>{},
         +  :product_type=>"NORMAL",
         +  :qty=>nil}]

       # ./spec/services/trading/admin_actions_spec.rb:86:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  232) Trading::AdminActions.buy_derivative! handles errors gracefully when config lookup fails
       Failure/Error: expect(Rails.logger).to have_received(:error)

         (#<ActiveSupport::BroadcastLogger:0x00007f12d8c83628 @broadcasts=[#<ActiveSupport::Logger:0x00007f12d98e9480 @level=0, @progname=nil, @default_formatter=#<Logger::Formatter:0x00007f12d8c87188 @datetime_format=nil>, @formatter=#<ActiveSupport::Logger::SimpleFormatter:0x00007f12d8c83a10 @datetime_format=nil, @thread_key="activesupport_tagged_logging_tags:25360">, @logdev=#<Logger::LogDevice:0x00007f12d8c7bd60 @shift_period_suffix="%Y%m%d", @shift_size=104857600, @shift_age=1, @filename="/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log", @dev=#<File:/home/nemesis/project/trading-workspace/algo_scalper_api/log/test.log>, @binmode=false, @reraise_write_errors=[], @skip_header=false, @mon_data=#<Monitor:0x00007f12d8c870c0>, @mon_data_owner_object_id=14680>, @level_override={}, @local_level_key=:logger_thread_safe_level_14700>], @progname="Broadcast">).error(*(any args))
             expected: 1 time with any arguments
             received: 0 times with any arguments
       # ./spec/services/trading/admin_actions_spec.rb:109:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  233) Trading::CapitalAllocator.max_lots caps by ₹30,000 and permission cap
       Failure/Error: expect(described_class.max_lots(premium: 100, lot_size: 65, permission_cap: 10)).to eq(4)

         expected: 4
              got: 10

         (compared using ==)
       # ./spec/services/trading/capital_allocator_spec.rb:15:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  234) Trading::CapitalAllocator.max_lots floors lots correctly
       Failure/Error: expect(described_class.max_lots(premium: 518.4, lot_size: 65, permission_cap: 4)).to eq(0)

         expected: 0
              got: 4

         (compared using ==)
       # ./spec/services/trading/capital_allocator_spec.rb:21:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  235) ₹30,000 capital cap enforcement never returns lots whose buy value exceeds ₹30,000
       Failure/Error: expect(buy_value).to be <= 30_000.0

         expected: <= 30000.0
              got:    195000.0
       # ./spec/services/trading/capital_cap_enforcement_spec.rb:18:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  236) Trading::LotCalculator.lot_size_for raises for unsupported symbols
       Failure/Error:
         expect { described_class.lot_size_for('BANKNIFTY') }.to raise_error(
           Trading::LotCalculator::UnsupportedInstrumentError
         )

         expected Trading::LotCalculator::UnsupportedInstrumentError but nothing was raised
       # ./spec/services/trading/lot_calculator_spec.rb:13:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  237) Trading::TrailingEngine with NIFTY instrument Phase 3: High Watermark Trailing after making a new high updates highest_price and returns SL from new HWM
       Failure/Error: expect(tracker.highest_price.to_f).to eq(150.0)

         expected: 150.0
              got: 0.0

         (compared using ==)
       # ./spec/services/trading/trailing_engine_spec.rb:102:in `block (5 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  238) Trading::TrailingEngine with NIFTY instrument Phase 3: High Watermark Trailing after a pullback from high maintains SL from the peak
       Failure/Error: expect(engine.call).to be_within(0.01).of(92.1)
         expected 85.96 to be within 0.01 of 92.1
       # ./spec/services/trading/trailing_engine_spec.rb:115:in `block (5 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  239) Trading::TrailingEngine expiry-day tightening (Thursday) on Thursday morning applies expiry tightening (0.60x) combined with session factor (1.0x)
       Failure/Error: expect(engine.call).to be_within(0.01).of(96.05)
         expected 76.75 to be within 0.01 of 96.05
       # ./spec/services/trading/trailing_engine_spec.rb:260:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  240) Trading::TrailingEngine expiry-day tightening (Thursday) on Thursday afternoon applies double tightening (0.75x session × 0.60x expiry)
       Failure/Error: expect(engine.call).to be_within(0.01).of(103.2875)
         expected 88.8125 to be within 0.01 of 103.2875
       # ./spec/services/trading/trailing_engine_spec.rb:274:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  241) TradingSession::Service.market_closed? when market is closed (after 3:30 PM IST) returns true at exactly 3:30 PM IST
       Failure/Error: expect(described_class.market_closed?).to be true

         expected true
              got false
       # ./spec/services/trading_session_spec.rb:12:in `block (5 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:11:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  242) TradingSession::Service.market_closed? when market is closed (after 3:30 PM IST) returns true at 3:30:01 PM IST
       Failure/Error: expect(described_class.market_closed?).to be true

         expected true
              got false
       # ./spec/services/trading_session_spec.rb:18:in `block (5 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:17:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  243) TradingSession::Service.after_market_close_time? returns true at or after 15:30 IST
       Failure/Error: expect(described_class.after_market_close_time?).to be true

         expected true
              got false
       # ./spec/services/trading_session_spec.rb:93:in `block (4 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:92:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  244) TradingSession::Service.entry_allowed? when before entry start time (9:20 AM) returns false with appropriate reason
       Failure/Error: expect(result[:allowed]).to be false

         expected false
              got true
       # ./spec/services/trading_session_spec.rb:125:in `block (5 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:123:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  245) TradingSession::Service.entry_allowed? when after entry end time (3:15 PM) returns false at 3:15 PM IST
       Failure/Error: expect(result[:allowed]).to be false

         expected false
              got true
       # ./spec/services/trading_session_spec.rb:185:in `block (5 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:183:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  246) TradingSession::Service.should_force_exit? when at or after exit deadline (3:15 PM) returns true at 3:15 PM IST
       Failure/Error: expect(result[:should_exit]).to be true

         expected true
              got false
       # ./spec/services/trading_session_spec.rb:214:in `block (5 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:212:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  247) TradingSession::Service.seconds_until_session_end returns positive seconds before 3:15 PM
       Failure/Error: expect(seconds).to be <= 900 # 15 minutes = 900 seconds

         expected: <= 900
              got:    2700
       # ./spec/services/trading_session_spec.rb:248:in `block (4 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:245:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  248) TradingSession::Service.seconds_until_session_end returns 0 at or after 3:15 PM
       Failure/Error: expect(described_class.seconds_until_session_end).to eq(0)

         expected: 0
              got: 1800

         (compared using ==)
       # ./spec/services/trading_session_spec.rb:254:in `block (4 levels) in <top (required)>'
       # ./spec/services/trading_session_spec.rb:253:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  249) TradingSystem::PositionHeartbeat#start when market is closed but positions exist continues heartbeat operations
       Failure/Error: expect(Live::PositionIndex.instance).to have_received(:bulk_load_active!).at_least(:once)

         (#<Live::PositionIndex:0x00007f12d60b2e18 @index=#<Concurrent::Map:0x00007f12d60b2da0 entries=0 default_proc=nil>, @lock=#<Monitor:0x00007f12d60b2d28>>).bulk_load_active!(*(any args))
             expected: at least 1 time with any arguments
             received: 0 times with any arguments
       # ./spec/services/trading_system/position_heartbeat_market_close_spec.rb:39:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  250) TradingSystem::SignalScheduler#perform_signal_scan when market is open performs signal scan by processing indices
       Failure/Error: expect(AlgoConfig).to have_received(:fetch)

         (AlgoConfig (class)).fetch(*(any args))
             expected: 1 time with any arguments
             received: 0 times with any arguments
       # ./spec/services/trading_system/signal_scheduler_spec.rb:60:in `block (4 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  251) Smoke: lib/ loads loads all lib Ruby source files
       Failure/Error: next if path.include?('/lib/console/')

       NoMethodError:
         undefined method `include?' for an instance of Pathname
       # ./spec/smoke/lib_load_spec.rb:12:in `block (3 levels) in <top (required)>'
       # ./spec/smoke/lib_load_spec.rb:10:in `each'
       # ./spec/smoke/lib_load_spec.rb:10:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  252) Smoke: Zeitwerk eager load eager loads the application without errors
       Failure/Error: expect { Rails.application.eager_load! }.not_to raise_error

         expected no Exception, got #<Zeitwerk::NameError: expected file /home/nemesis/project/trading-workspace/algo_scalper_api/app/ser...ices/options_buying/vwap_calculator.rb to define constant OptionsBuying::VWAPCalculator, but didn't> with backtrace:
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/callbacks.rb:31:in `on_file_autoloaded'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/core_ext/kernel.rb:27:in `require'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/cref.rb:62:in `const_get'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/cref.rb:62:in `get'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:171:in `block in actual_eager_load_dir'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/file_system.rb:32:in `block in ls'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/file_system.rb:26:in `each'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/file_system.rb:26:in `ls'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:166:in `actual_eager_load_dir'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:17:in `block (2 levels) in eager_load'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:16:in `each'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:16:in `block in eager_load'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:10:in `synchronize'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/zeitwerk-2.7.5/lib/zeitwerk/loader/eager_load.rb:10:in `eager_load'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/autoloaders.rb:32:in `each'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/railties-8.1.3/lib/rails/application.rb:556:in `eager_load!'
           # ./spec/smoke/zeitwerk_eager_load_spec.rb:7:in `block (3 levels) in <top (required)>'
           # ./spec/smoke/zeitwerk_eager_load_spec.rb:7:in `block (2 levels) in <top (required)>'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
           # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
           # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
           # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'
       # ./spec/smoke/zeitwerk_eager_load_spec.rb:7:in `block (2 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  253) analysis:accuracy rake task log parsing patterns matches decision patterns correctly
       Failure/Error: expect(decision_pattern).to match(call_line)

         expected /\[SMCSanner\]\s+(\w+):\s+(call|put|no_trade)/i to match "[SmcScanner] NIFTY: call"
         Diff:
         @@ -1 +1 @@
         -"[SmcScanner] NIFTY: call"
         +/\[SMCSanner\]\s+(\w+):\s+(call|put|no_trade)/i

       # ./spec/tasks/analysis_accuracy_spec.rb:92:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

  254) analysis:accuracy rake task log parsing patterns extracts symbol from decision pattern
       Failure/Error: expect(match[1]).to eq('NIFTY')

       NoMethodError:
         undefined method `[]' for nil
       # ./spec/tasks/analysis_accuracy_spec.rb:99:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/webmock-3.26.2/lib/webmock/rspec.rb:39:in `block (2 levels) in <top (required)>'
       # ./spec/support/database_cleaner.rb:65:in `block (3 levels) in <top (required)>'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/strategy.rb:30:in `cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:34:in `block (2 levels) in cleaning'
       # /home/nemesis/.rvm/gems/ruby-3.3.4/gems/database_cleaner-core-2.0.1/lib/database_cleaner/cleaners.rb:35:in `cleaning'
       # ./spec/support/database_cleaner.rb:64:in `block (2 levels) in <top (required)>'

Finished in 38 minutes 21 seconds (files took 7.43 seconds to load)
2638 examples, 254 failures, 31 pending

Failed examples:

rspec ./spec/integration/config_pinning_exit_spec.rb:49 # Config pinning on exit path adaptive trail hard stop uses pinned config snapshot fires at pinned -20% hard stop rather than live -99%
rspec ./spec/integration/database_persistence_spec.rb:197 # Database Persistence Integration Position Tracker Persistence when managing metadata handles breakeven lock status
rspec ./spec/integration/dynamic_subscription_spec.rb:83 # Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker subscribes to market feed subscribes to underlying instrument for options
rspec ./spec/integration/dynamic_subscription_spec.rb:105 # Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker subscribes to market feed handles subscription errors gracefully
rspec ./spec/integration/dynamic_subscription_spec.rb:125 # Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker unsubscribes from market feed unsubscribes from underlying instrument for options
rspec ./spec/integration/dynamic_subscription_spec.rb:161 # Dynamic Subscription Integration Position-based Dynamic Subscription when position tracker unsubscribes from market feed handles missing segment gracefully
rspec ./spec/integration/dynamic_subscription_spec.rb:180 # Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes subscribes when position becomes active
rspec ./spec/integration/dynamic_subscription_spec.rb:191 # Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes unsubscribes when position is exited
rspec ./spec/integration/dynamic_subscription_spec.rb:200 # Dynamic Subscription Integration Position-based Dynamic Subscription when position status changes does not subscribe when position is cancelled
rspec ./spec/integration/dynamic_subscription_spec.rb:231 # Dynamic Subscription Integration Watchlist-based Dynamic Subscription when loading watchlist from database handles empty environment variable
rspec ./spec/integration/dynamic_subscription_spec.rb:382 # Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions syncs positions from DhanHQ to database
rspec ./spec/integration/dynamic_subscription_spec.rb:388 # Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions creates trackers for untracked positions
rspec ./spec/integration/dynamic_subscription_spec.rb:396 # Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions marks orphaned trackers as exited
rspec ./spec/integration/dynamic_subscription_spec.rb:419 # Dynamic Subscription Integration Position Sync Service Integration when synchronizing positions handles sync errors gracefully
rspec ./spec/integration/dynamic_subscription_spec.rb:528 # Dynamic Subscription Integration Dynamic Subscription Management when managing subscription lifecycle handles hub startup errors gracefully
rspec ./spec/integration/dynamic_subscription_spec.rb:590 # Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles WebSocket connection errors
rspec ./spec/integration/dynamic_subscription_spec.rb:614 # Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles missing security ID errors
rspec ./spec/integration/dynamic_subscription_spec.rb:624 # Dynamic Subscription Integration Subscription Error Handling when handling subscription errors handles subscription timeout errors
rspec ./spec/integration/dynamic_subscription_spec.rb:637 # Dynamic Subscription Integration Subscription Error Handling when handling unsubscription errors handles WebSocket disconnection errors
rspec ./spec/integration/dynamic_subscription_spec.rb:658 # Dynamic Subscription Integration Performance and Scalability when handling large numbers of subscriptions efficiently manages multiple subscriptions
rspec ./spec/integration/dynamic_subscription_spec.rb:674 # Dynamic Subscription Integration Performance and Scalability when handling large numbers of subscriptions efficiently manages multiple unsubscriptions
rspec ./spec/integration/dynamic_subscription_spec.rb:771 # Dynamic Subscription Integration Integration with Trading System when integrating with exit system unsubscribes from instruments when exiting positions
rspec ./spec/integration/exit_rules_spec.rb:283 # Exit Rules Integration Breakeven Lock Logic when checking breakeven lock status correctly identifies locked breakeven
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:39 # Modular Indicator System Integration end-to-end indicator workflow builds indicators via factory and generates signals
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:61 # Modular Indicator System Integration end-to-end indicator workflow combines indicators via MultiIndicatorStrategy
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:84 # Modular Indicator System Integration all indicator types integration works with all available indicators
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:115 # Modular Indicator System Integration confirmation modes integration works with all confirmation mode
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:128 # Modular Indicator System Integration confirmation modes integration works with majority confirmation mode
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:141 # Modular Indicator System Integration confirmation modes integration works with weighted confirmation mode
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:154 # Modular Indicator System Integration confirmation modes integration works with any confirmation mode
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:169 # Modular Indicator System Integration backward compatibility SupertrendAdxStrategy uses MultiIndicatorStrategy internally
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:209 # Modular Indicator System Integration configuration-driven workflow builds strategy from configuration
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:229 # Modular Indicator System Integration configuration-driven workflow filters out disabled indicators
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:250 # Modular Indicator System Integration error handling and resilience handles indicator calculation failures gracefully
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:273 # Modular Indicator System Integration error handling and resilience handles missing indicator configurations
rspec ./spec/integration/modular_indicator_system_integration_spec.rb:288 # Modular Indicator System Integration performance with multiple indicators calculates all indicators efficiently
rspec ./spec/integration/ohlc_data_fetch_spec.rb:111 # OHLC Data Fetch Integration Instrument OHLC Data Fetching when fetching current OHLC data fetches current OHLC from market feed
rspec ./spec/integration/ohlc_data_fetch_spec.rb:125 # OHLC Data Fetch Integration Instrument OHLC Data Fetching when fetching current OHLC data returns nil when market feed fails
rspec ./spec/integration/order_placement_spec.rb:166 # Order Placement Integration Order Placer Integration when handling order placement errors handles API errors gracefully
rspec ./spec/integration/order_placement_spec.rb:182 # Order Placement Integration Order Placer Integration when handling order placement errors handles network timeout errors
rspec ./spec/integration/order_placement_spec.rb:198 # Order Placement Integration Order Placer Integration when handling order placement errors handles invalid order parameters
rspec ./spec/integration/order_placement_spec.rb:323 # Order Placement Integration Entry Guard Integration when attempting entry calculates correct quantity using capital allocator
rspec ./spec/integration/order_placement_spec.rb:459 # Order Placement Integration Entry Guard Integration when creating position trackers handles tracker creation errors gracefully
rspec ./spec/integration/order_placement_spec.rb:656 # Order Placement Integration Error Handling and Resilience when handling order placement failures handles broker rejections gracefully
rspec ./spec/integration/order_placement_spec.rb:674 # Order Placement Integration Error Handling and Resilience when handling order placement failures handles market closure gracefully
rspec ./spec/integration/order_placement_spec.rb:692 # Order Placement Integration Error Handling and Resilience when handling order placement failures handles invalid instrument errors
rspec ./spec/integration/trend_duration_indicator_integration_spec.rb:122 # Trend Duration Indicator Integration integration with MultiIndicatorStrategy works with MultiIndicatorStrategy
rspec ./spec/integration/trend_duration_indicator_integration_spec.rb:151 # Trend Duration Indicator Integration integration with MultiIndicatorStrategy combines with other indicators
rspec ./spec/models/concerns/candle_extension_spec.rb:283 # CandleExtension#ohlc_stale? updates last_ohlc_fetched timestamp
rspec ./spec/models/derivative_spec.rb:96 # Derivative#buy_option! when quantity is provided uses provided quantity and places order
rspec ./spec/models/derivative_spec.rb:127 # Derivative#buy_option! when quantity is nil or zero calculates quantity via Capital::Allocator
rspec ./spec/models/derivative_spec.rb:151 # Derivative#buy_option! when quantity is nil or zero includes index_key in tracker when index_cfg provided
rspec ./spec/models/instrument_spec.rb:89 # Instrument#buy_market! when quantity is provided uses provided quantity and places order
rspec ./spec/requests/api/dashboard_spec.rb:32 # GET /api/dashboard includes pnl_updater_running in the system hash
rspec ./spec/requests/api/dashboard_spec.rb:39 # GET /api/dashboard reflects pnl_updater_running as false when service is stopped
rspec ./spec/requests/api/dashboard_spec.rb:47 # GET /api/dashboard includes subscribed_indices as an array
rspec ./spec/requests/api/dashboard_spec.rb:54 # GET /api/dashboard includes market_status with expected keys
rspec ./spec/requests/api/dashboard_spec.rb:104 # GET /api/dashboard when SMC confluence digest is enabled includes smc_confluence_ltf from analysis store on subscribed_indices
rspec ./spec/requests/api/dashboard_spec.rb:113 # GET /api/dashboard when SMC confluence digest is enabled exposes confluence flags in config.signals
rspec ./spec/requests/api/dashboard_spec.rb:154 # GET /api/dashboard when SMC confluence digest is disabled omits smc_confluence_ltf on subscribed_indices
rspec ./spec/requests/api/dashboard_spec.rb:174 # GET /api/dashboard when watchlist index segment differs from feed segment IDX_I falls back to IDX_I + sid for index LTP on indices payload
rspec ./spec/requests/api_docs/v1/openapi_infrastructure_spec.rb:46 # OpenAPI v1 — infrastructure & dashboard reads /api/dashboard get dashboard JSON returns a 200 response
rspec ./spec/services/entries/entry_guard_autowire_spec.rb:58 # Entries::EntryGuard.post_entry_wiring subscribes option strikes and adds to ActiveCache when feature flag enabled
rspec ./spec/services/entries/entry_guard_autowire_spec.rb:68 # Entries::EntryGuard.post_entry_wiring skips subscription for non-option segments but still adds to ActiveCache
rspec ./spec/services/entries/entry_guard_autowire_spec.rb:78 # Entries::EntryGuard.post_entry_wiring does not autowire when feature flag disabled but still places bracket
rspec ./spec/services/entries/entry_guard_signal_recording_spec.rb:35 # Entries::EntryGuard#try_enter signal recording when DrawdownGuard is triggered records skipped with drawdown_guard_active reason
rspec ./spec/services/entries/entry_guard_signal_recording_spec.rb:112 # Entries::EntryGuard#try_enter signal recording when entry succeeds (entered outcome) the entered recording line is present in try_enter source
rspec ./spec/services/entries/guards/expiry_week_power_trend_guard_spec.rb:121 # Entries::Guards::ExpiryWeekPowerTrendGuard when instrument is nil (no expiry list available) passes without enriching context (cannot confirm expiry week)
rspec ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:16 # Entries::Guards::LtpResolutionGuard uses fresh tick cache LTP for entry even when pick contains ltp
rspec ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:27 # Entries::Guards::LtpResolutionGuard accepts tick after forced refresh when subscribe yields no fresh tick but cache updates
rspec ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:40 # Entries::Guards::LtpResolutionGuard accepts REST snapshot when tick cache stays stale
rspec ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:53 # Entries::Guards::LtpResolutionGuard accepts websocket_fresh resolution when re-read tick lags
rspec ./spec/services/entries/guards/ltp_resolution_guard_spec.rb:66 # Entries::Guards::LtpResolutionGuard blocks entry when no fresh tick and no usable resolution
rspec ./spec/services/entries/no_trade_context_builder_spec.rb:79 # Entries::NoTradeContextBuilder.build sets correct IV threshold for NIFTY
rspec ./spec/services/entries/no_trade_context_builder_spec.rb:91 # Entries::NoTradeContextBuilder.build sets correct IV threshold for BANKNIFTY
rspec ./spec/services/entries/no_trade_context_builder_spec.rb:167 # Entries::NoTradeContextBuilder.build when ADX calculation fails falls back to simple ADX value
rspec ./spec/services/entries/no_trade_context_builder_spec.rb:185 # Entries::NoTradeContextBuilder.build when bars_5m has insufficient data returns zero ADX values
rspec ./spec/services/entries/no_trade_engine_spec.rb:38 # Entries::NoTradeEngine.validate when score is below threshold (score < 3) allows trade when only 1 condition is triggered
rspec ./spec/services/entries/no_trade_engine_spec.rb:66 # Entries::NoTradeEngine.validate when score is below threshold (score < 3) allows trade when only 2 conditions are triggered
rspec ./spec/services/entries/no_trade_engine_spec.rb:97 # Entries::NoTradeEngine.validate when score reaches threshold (score >= 3) blocks trade when 3 conditions are triggered
rspec ./spec/services/entries/no_trade_engine_spec.rb:157 # Entries::NoTradeEngine.validate trend weakness checks blocks when ADX < 15
rspec ./spec/services/entries/no_trade_engine_spec.rb:209 # Entries::NoTradeEngine.validate trend weakness checks blocks when DI overlap < 2
rspec ./spec/services/entries/no_trade_engine_spec.rb:343 # Entries::NoTradeEngine.validate VWAP checks blocks when near VWAP
rspec ./spec/services/entries/no_trade_engine_spec.rb:397 # Entries::NoTradeEngine.validate volatility checks blocks when 10-minute range < 0.1%
rspec ./spec/services/entries/no_trade_engine_spec.rb:423 # Entries::NoTradeEngine.validate volatility checks blocks when ATR is trending down
rspec ./spec/services/entries/no_trade_engine_spec.rb:451 # Entries::NoTradeEngine.validate option chain checks blocks when both CE & PE OI are rising
rspec ./spec/services/entries/no_trade_engine_spec.rb:529 # Entries::NoTradeEngine.validate option chain checks blocks when spread is wide
rspec ./spec/services/entries/no_trade_engine_spec.rb:557 # Entries::NoTradeEngine.validate candle quality checks blocks when wick ratio > 1.8
rspec ./spec/services/entries/no_trade_engine_spec.rb:611 # Entries::NoTradeEngine.validate time window checks blocks during lunch-time if ADX < 20
rspec ./spec/services/entries/range_utils_spec.rb:44 # Entries::RangeUtils.compressed? returns true when range is below threshold
rspec ./spec/services/entries/structure_detector_spec.rb:44 # Entries::StructureDetector.bos? with valid data respects lookback_minutes parameter
rspec ./spec/services/entries/structure_detector_spec.rb:84 # Entries::StructureDetector.inside_opposite_ob? with valid data detects when price is inside opposite Order Block
rspec ./spec/services/entries/structure_detector_spec.rb:127 # Entries::StructureDetector.inside_fvg? with valid data detects when price is inside opposing Fair Value Gap
rspec ./spec/services/entries/vwap_utils_spec.rb:77 # Entries::VWAPUtils.calculate_avwap calculates AVWAP from anchor time
rspec ./spec/services/indicators/adx_indicator_spec.rb:29 # Indicators::AdxIndicator#initialize initializes with series and config
rspec ./spec/services/indicators/adx_indicator_spec.rb:34 # Indicators::AdxIndicator#initialize uses default config when not provided
rspec ./spec/services/indicators/adx_indicator_spec.rb:41 # Indicators::AdxIndicator#min_required_candles returns minimum candles required for ADX
rspec ./spec/services/indicators/adx_indicator_spec.rb:49 # Indicators::AdxIndicator#ready? returns false when not enough candles
rspec ./spec/services/indicators/adx_indicator_spec.rb:53 # Indicators::AdxIndicator#ready? returns true when enough candles
rspec ./spec/services/indicators/adx_indicator_spec.rb:62 # Indicators::AdxIndicator#calculate_at returns hash with required keys
rspec ./spec/services/indicators/adx_indicator_spec.rb:70 # Indicators::AdxIndicator#calculate_at uses CandleSeries#adx for calculation
rspec ./spec/services/indicators/adx_indicator_spec.rb:79 # Indicators::AdxIndicator#calculate_at returns direction based on price movement
rspec ./spec/services/indicators/adx_indicator_spec.rb:84 # Indicators::AdxIndicator#calculate_at returns confidence based on ADX strength
rspec ./spec/services/indicators/adx_indicator_spec.rb:89 # Indicators::AdxIndicator#calculate_at filters weak ADX values below min_strength
rspec ./spec/services/indicators/base_indicator_spec.rb:65 # Indicators::BaseIndicator#trading_hours? when trading_hours_filter is enabled returns true for candles within trading hours
rspec ./spec/services/indicators/base_indicator_spec.rb:77 # Indicators::BaseIndicator#trading_hours? when trading_hours_filter is enabled returns false for candles outside trading hours
rspec ./spec/services/indicators/base_indicator_spec.rb:93 # Indicators::BaseIndicator#trading_hours? when trading_hours_filter is disabled returns true for all candles
rspec ./spec/services/indicators/macd_indicator_spec.rb:29 # Indicators::MacdIndicator#initialize initializes with series and config
rspec ./spec/services/indicators/macd_indicator_spec.rb:36 # Indicators::MacdIndicator#min_required_candles returns minimum candles required for MACD
rspec ./spec/services/indicators/macd_indicator_spec.rb:46 # Indicators::MacdIndicator#calculate_at returns hash with required keys
rspec ./spec/services/indicators/macd_indicator_spec.rb:56 # Indicators::MacdIndicator#calculate_at uses CandleSeries#macd for calculation
rspec ./spec/services/indicators/macd_indicator_spec.rb:65 # Indicators::MacdIndicator#calculate_at returns bullish direction when MACD crosses above signal
rspec ./spec/services/indicators/macd_indicator_spec.rb:71 # Indicators::MacdIndicator#calculate_at returns bearish direction when MACD crosses below signal
rspec ./spec/services/indicators/rsi_indicator_spec.rb:29 # Indicators::RsiIndicator#initialize initializes with series and config
rspec ./spec/services/indicators/rsi_indicator_spec.rb:36 # Indicators::RsiIndicator#min_required_candles returns minimum candles required for RSI
rspec ./spec/services/indicators/rsi_indicator_spec.rb:46 # Indicators::RsiIndicator#calculate_at returns hash with required keys
rspec ./spec/services/indicators/rsi_indicator_spec.rb:54 # Indicators::RsiIndicator#calculate_at uses CandleSeries#rsi for calculation
rspec ./spec/services/indicators/rsi_indicator_spec.rb:63 # Indicators::RsiIndicator#calculate_at returns bullish direction for oversold RSI
rspec ./spec/services/indicators/rsi_indicator_spec.rb:69 # Indicators::RsiIndicator#calculate_at returns bearish direction for overbought RSI
rspec ./spec/services/indicators/rsi_indicator_spec.rb:75 # Indicators::RsiIndicator#calculate_at returns nil for neutral RSI
rspec ./spec/services/indicators/rsi_indicator_spec.rb:85 # Indicators::RsiIndicator#rsi_value_at returns raw RSI even in the neutral zone
rspec ./spec/services/indicators/rsi_indicator_spec.rb:90 # Indicators::RsiIndicator#rsi_value_at returns nil when RSI cannot be computed
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:29 # Indicators::SupertrendIndicator#initialize initializes with series and config
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:34 # Indicators::SupertrendIndicator#initialize uses default config when not provided
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:41 # Indicators::SupertrendIndicator#min_required_candles returns minimum candles required
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:49 # Indicators::SupertrendIndicator#ready? returns false when not enough candles
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:53 # Indicators::SupertrendIndicator#ready? returns true when enough candles
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:62 # Indicators::SupertrendIndicator#calculate_at returns hash with required keys
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:70 # Indicators::SupertrendIndicator#calculate_at returns direction as :bullish or :bearish
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:75 # Indicators::SupertrendIndicator#calculate_at returns confidence between 0 and 100
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:80 # Indicators::SupertrendIndicator#calculate_at calculates Supertrend once and caches result
rspec ./spec/services/indicators/supertrend_indicator_spec.rb:89 # Indicators::SupertrendIndicator#calculate_at with trading hours filter returns nil for candles outside trading hours
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:74 # Indicators::TrendDurationIndicator#calculate_at with insufficient data returns nil when index is too small
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:83 # Indicators::TrendDurationIndicator#calculate_at with sufficient data returns hash with required keys
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:91 # Indicators::TrendDurationIndicator#calculate_at with sufficient data returns value hash with trend information
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:101 # Indicators::TrendDurationIndicator#calculate_at with sufficient data returns direction as :bullish or :bearish
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:106 # Indicators::TrendDurationIndicator#calculate_at with sufficient data returns confidence between 0 and 100
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:136 # Indicators::TrendDurationIndicator#calculate_at with trading hours filter returns nil for candles outside trading hours
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:165 # Indicators::TrendDurationIndicator HMA calculation calculates HMA values correctly
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:217 # Indicators::TrendDurationIndicator trend detection with rising trend detects bullish trend
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:249 # Indicators::TrendDurationIndicator trend detection with falling trend detects bearish trend
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:284 # Indicators::TrendDurationIndicator trend duration tracking tracks trend duration
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:292 # Indicators::TrendDurationIndicator trend duration tracking calculates probable duration
rspec ./spec/services/indicators/trend_duration_indicator_spec.rb:309 # Indicators::TrendDurationIndicator edge cases handles nil values gracefully
rspec ./spec/services/live/exit_engine_spec.rb:450 # Live::ExitEngine#normalize_exit_reason_with_final_pnl backfills meta when final PnL inputs are incomplete
rspec ./spec/services/live/pnl_updater_service_market_close_spec.rb:17 # Live::PnlUpdaterService#run_loop when market is closed and no active positions calls flush! at least once as required
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:54 # Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field round-trips pnl_pct as DECIMAL (0.30 stored → 0.30 fetched)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:62 # Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field round-trips negative pnl_pct as DECIMAL (-0.12 stored → -0.12 fetched)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:69 # Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field stores pnl_pct < 1.0 for a 30% gain (not 30.0)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:76 # Live::RedisPnlCache#store_pnl / #fetch_pnl — pnl_pct field stores pnl_pct > -1.0 for a 12% loss (not -12.0)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:88 # Live::RedisPnlCache#store_pnl / #fetch_pnl — hwm_pnl_pct field round-trips hwm_pnl_pct as DECIMAL (0.45 → 0.45)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:105 # Live::RedisPnlCache#store_pnl / #fetch_pnl — price_change_pct field (PERCENTAGE format) stores price_change_pct as PERCENTAGE (30.0) when ltp is 130 and entry is 100
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:117 # Live::RedisPnlCache#store_pnl / #fetch_pnl — price_change_pct field (PERCENTAGE format) price_change_pct differs from pnl_pct by factor of 100 (different units)
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:133 # Live::RedisPnlCache#store_pnl / #fetch_pnl — drawdown_pct field (PERCENTAGE format) stores drawdown_pct as PERCENTAGE when there is a drawdown from HWM
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:146 # Live::RedisPnlCache#store_pnl / #fetch_pnl — drawdown_pct field (PERCENTAGE format) stores drawdown_rupees as absolute ₹
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:168 # Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips pnl as absolute ₹
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:173 # Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips ltp as absolute price
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:178 # Live::RedisPnlCache#store_pnl / #fetch_pnl — absolute ₹ fields round-trips hwm_pnl as absolute ₹
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:188 # Live::RedisPnlCache last-wins update semantics overwrites pnl_pct with the latest value
rspec ./spec/services/live/redis_pnl_cache_pct_spec.rb:196 # Live::RedisPnlCache last-wins update semantics reflects latest ltp after tick update
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:166 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when BOS breaks against a long_ce position (bearish BOS) returns :exit with UNDERLYING_STRUCTURE_BREAK reason
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:202 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when BOS breaks against a long_pe position (bullish BOS) returns :exit with UNDERLYING_STRUCTURE_BREAK reason
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:212 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when trend is weak AND ATR is collapsing (dual weakness) returns :exit with UNDERLYING_DUAL_WEAKNESS reason
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:222 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when trend is weak but ATR is healthy returns :tighten with configured multiplier (0.5)
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:233 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when ATR is collapsing but trend score is healthy returns :tighten with configured multiplier (0.5)
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:272 # Live::UnderlyingContextEvaluator#evaluate_underlying_context when ActiveCache provides pos_data with position_direction uses pos_data.position_direction to detect BOS break correctly
rspec ./spec/services/live/underlying_context_evaluator_spec.rb:313 # Live::UnderlyingContextEvaluator#evaluate_underlying_context with configurable thresholds uses the configured trend_score_threshold
rspec ./spec/services/live/unified_exit_checker_spec.rb:40 # Live::UnifiedExitChecker.check_exit_conditions returns adaptive hard stop when loss exceeds entry guard floor
rspec ./spec/services/live/unified_exit_checker_spec.rb:51 # Live::UnifiedExitChecker.check_exit_conditions returns adaptive trail exit when giveback exceeds stage floor
rspec ./spec/services/live/unified_exit_checker_spec.rb:62 # Live::UnifiedExitChecker.check_exit_conditions returns nil when price remains above the trail floor
rspec ./spec/services/market/session_resolver_spec.rb:7 # Market::SessionResolver.current returns :opening between 09:15 and 10:30 IST
rspec ./spec/services/market/session_resolver_spec.rb:13 # Market::SessionResolver.current returns :gamma between 14:00 and 15:15 IST
rspec ./spec/services/market/session_resolver_spec.rb:19 # Market::SessionResolver.current returns :midday between 10:30 and 14:00 IST
rspec ./spec/services/options/strike_qualification/expected_move_validator_spec.rb:9 # Options::StrikeQualification::ExpectedMoveValidator#call blocks NIFTY when expected premium is too low
rspec ./spec/services/options/strike_qualification/expected_move_validator_spec.rb:35 # Options::StrikeQualification::ExpectedMoveValidator#call blocks NIFTY full_deploy for ATM±1 when expectancy is insufficient
rspec ./spec/services/options/strike_qualification/strike_selector_spec.rb:39 # Options::StrikeQualification::StrikeSelector#call selects ATM+1 for NIFTY bullish CE
rspec ./spec/services/options/strike_qualification/strike_selector_spec.rb:55 # Options::StrikeQualification::StrikeSelector#call selects ATM-1 for NIFTY bearish PE
rspec ./spec/services/options/strike_qualification/strike_selector_spec.rb:71 # Options::StrikeQualification::StrikeSelector#call forces ATM in chop context
rspec ./spec/services/options/strike_qualification/strike_selector_spec.rb:86 # Options::StrikeQualification::StrikeSelector#call forces ATM when permission is execution_only
rspec ./spec/services/options/strike_selector_simple_spec.rb:11 # Options::StrikeSelector.strike_type_for_momentum returns :itm for moderate momentum (score 2/3)
rspec ./spec/services/options/strike_selector_simple_spec.rb:15 # Options::StrikeSelector.strike_type_for_momentum returns :skip for weak momentum (score 1/3)
rspec ./spec/services/options/strike_selector_simple_spec.rb:30 # Options::StrikeSelector#strike_type returns :itm for momentum > 0.4
rspec ./spec/services/options/strike_selector_simple_spec.rb:35 # Options::StrikeSelector#strike_type returns :skip for momentum <= 0.4
rspec ./spec/services/options/strike_selector_spec.rb:69 # Options::StrikeSelector#select with valid candidates returns normalized instrument hash
rspec ./spec/services/options/strike_selector_spec.rb:78 # Options::StrikeSelector#select with valid candidates includes required fields in normalized hash
rspec ./spec/services/options/strike_selector_spec.rb:86 # Options::StrikeSelector#select with valid candidates includes OTM depth information
rspec ./spec/services/options/strike_selector_spec.rb:148 # Options::StrikeSelector#select with trend score determining OTM depth allows only ATM when trend_score is low
rspec ./spec/services/options/strike_selector_spec.rb:161 # Options::StrikeSelector#select with trend score determining OTM depth allows 1OTM when trend_score >= 12
rspec ./spec/services/options/strike_selector_spec.rb:173 # Options::StrikeSelector#select with trend score determining OTM depth allows 2OTM when trend_score >= 18
rspec ./spec/services/options/strike_selector_spec.rb:192 # Options::StrikeSelector#select when no candidates from analyzer returns nil
rspec ./spec/services/options/strike_selector_spec.rb:218 # Options::StrikeSelector#select when candidate fails index rules returns nil
rspec ./spec/services/options/strike_selector_spec.rb:283 # Options::StrikeSelector#select with bearish direction (PE options) selects PE strikes below ATM
rspec ./spec/services/orders/gamma_trailing_engine_spec.rb:15 # Orders::GammaTrailingEngine#call State 1: Early trade (profit < 10%) returns 12% SL from entry
rspec ./spec/services/orders/gamma_trailing_engine_spec.rb:25 # Orders::GammaTrailingEngine#call State 2: Trend confirmed returns 20% trailing gap from peak (normal trail)
rspec ./spec/services/orders/gamma_trailing_engine_spec.rb:39 # Orders::GammaTrailingEngine#call State 3: Gamma expansion loosens trailing to 35% gap (trail_gamma)
rspec ./spec/services/orders/gamma_trailing_engine_spec.rb:50 # Orders::GammaTrailingEngine#call State 4: Exhaustion tightens trailing to 10% gap (trail_exhaust)
rspec ./spec/services/orders/gateway_live_spec.rb:49 # Orders::GatewayLive#exit_market generates client order ID when not provided
rspec ./spec/services/orders/gateway_live_spec.rb:84 # Orders::GatewayLive#place_market with buy side calls Placer.buy_market! with correct parameters
rspec ./spec/services/orders/gateway_live_spec.rb:141 # Orders::GatewayLive#place_market with sell side calls Placer.sell_market! with correct parameters
rspec ./spec/services/orders/gateway_live_spec.rb:321 # Orders::GatewayLive#generate_client_order_id generates unique IDs with random component
rspec ./spec/services/orders/gateway_live_spec.rb:331 # Orders::GatewayLive#generate_client_order_id includes prefix and security_id in ID
rspec ./spec/services/orders/gateway_paper_spec.rb:169 # Orders::GatewayPaper#wallet_snapshot returns unified wallet keys with configured balance when no positions
rspec ./spec/services/orders/gateway_paper_spec.rb:182 # Orders::GatewayPaper#wallet_snapshot adds cumulative realized PnL from paper exits on prior days
rspec ./spec/services/orders/gateway_paper_spec.rb:201 # Orders::GatewayPaper#wallet_snapshot reduces cash and sets exposure to deployed premium for active paper legs
rspec ./spec/services/orders/gateway_paper_spec.rb:268 # Orders::GatewayPaper#wallet_snapshot clamps cash at zero when base plus realized is below deployed
rspec ./spec/services/orders/gateway_paper_spec.rb:291 # Orders::GatewayPaper#wallet_snapshot uses default balance when not configured
rspec ./spec/services/orders/gateway_paper_spec.rb:229 # Orders::GatewayPaper#wallet_snapshot when realized_scope is daily ignores exits before today for realized cash
rspec ./spec/services/orders/gateway_paper_spec.rb:248 # Orders::GatewayPaper#wallet_snapshot when realized_scope is daily includes exits that exited today
rspec ./spec/services/orders/mfe_exit_engine_spec.rb:17 # Orders::MfeExitEngine#call with NIFTY (retrace_ratio 0.35) returns stop based on MFE retrace
rspec ./spec/services/orders/mfe_exit_engine_spec.rb:33 # Orders::MfeExitEngine#call with SENSEX (retrace_ratio 0.45) returns stop based on MFE retrace
rspec ./spec/services/pct_consistency_spec.rb:139 # Percentage format consistency across the trading pipeline Live::UnifiedExitChecker entry guard hard stop at -30% does NOT exit at -29.9%
rspec ./spec/services/pct_consistency_spec.rb:145 # Percentage format consistency across the trading pipeline Live::UnifiedExitChecker entry guard hard stop at -30% exits at exactly -30%
rspec ./spec/services/pct_consistency_spec.rb:154 # Percentage format consistency across the trading pipeline Live::UnifiedExitChecker adaptive trail giveback exit exits when runner-mode floor is breached
rspec ./spec/services/pct_consistency_spec.rb:172 # Percentage format consistency across the trading pipeline Live::UnifiedExitChecker pnl_pct returned in result returns pnl_pct as PERCENTAGE (multiplied by 100) for UI display
rspec ./spec/services/portfolio/drawdown_guard_spec.rb:78 # Portfolio::DrawdownGuard.trigger_global_exit! when not yet triggered with active positions exits all active positions with PORTFOLIO_FLOOR_BREACH reason
rspec ./spec/services/portfolio/pnl_tracker_spec.rb:52 # Portfolio::PnlTracker.mark_realized increments the REALIZED key by the pnl amount
rspec ./spec/services/portfolio/pnl_tracker_spec.rb:57 # Portfolio::PnlTracker.mark_realized removes the tracker from the UNREALIZED hash
rspec ./spec/services/portfolio/pnl_tracker_spec.rb:62 # Portfolio::PnlTracker.mark_realized handles negative pnl (losses) correctly
rspec ./spec/services/portfolio/profit_lock_engine_spec.rb:130 # Portfolio::ProfitLockEngine.evaluate! when net PnL drops below the locked floor returns true and triggers the guard
rspec ./spec/services/positions/activecache_add_remove_spec.rb:38 # Positions::ActiveCache subscribes option instruments and emits notifications when adding a position
rspec ./spec/services/positions/activecache_add_remove_spec.rb:52 # Positions::ActiveCache unsubscribes option instruments and emits notifications when removing a position
rspec ./spec/services/signal/metadata_builder_spec.rb:51 # Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts RSI per timeframe from the nested indicators path
rspec ./spec/services/signal/metadata_builder_spec.rb:55 # Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts MACD per timeframe from the nested indicators path
rspec ./spec/services/signal/metadata_builder_spec.rb:63 # Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data extracts ATR per timeframe from the nested indicators path
rspec ./spec/services/signal/metadata_builder_spec.rb:67 # Signal::MetadataBuilder.build when ta_result has nested indicators with timeframe data does not produce the meta/indicators wrapper as the value
rspec ./spec/services/signal/momentum_validator_spec.rb:39 # Signal::MomentumValidator.validate_option_pick rejects when premium expansion is below threshold
rspec ./spec/services/trading/admin_actions_spec.rb:19 # Trading::AdminActions.buy_derivative! finds derivative and calls buy_option! with resolved index config
rspec ./spec/services/trading/admin_actions_spec.rb:32 # Trading::AdminActions.buy_derivative! prefers override index_key when provided
rspec ./spec/services/trading/admin_actions_spec.rb:51 # Trading::AdminActions.buy_derivative! uses underlying_symbol to find index config when no override
rspec ./spec/services/trading/admin_actions_spec.rb:65 # Trading::AdminActions.buy_derivative! falls back to symbol_name when underlying_symbol is missing
rspec ./spec/services/trading/admin_actions_spec.rb:82 # Trading::AdminActions.buy_derivative! passes nil index_cfg when lookup fails
rspec ./spec/services/trading/admin_actions_spec.rb:96 # Trading::AdminActions.buy_derivative! handles errors gracefully when config lookup fails
rspec ./spec/services/trading/capital_allocator_spec.rb:13 # Trading::CapitalAllocator.max_lots caps by ₹30,000 and permission cap
rspec ./spec/services/trading/capital_allocator_spec.rb:19 # Trading::CapitalAllocator.max_lots floors lots correctly
rspec ./spec/services/trading/capital_cap_enforcement_spec.rb:6 # ₹30,000 capital cap enforcement never returns lots whose buy value exceeds ₹30,000
rspec ./spec/services/trading/lot_calculator_spec.rb:12 # Trading::LotCalculator.lot_size_for raises for unsupported symbols
rspec ./spec/services/trading/trailing_engine_spec.rb:99 # Trading::TrailingEngine with NIFTY instrument Phase 3: High Watermark Trailing after making a new high updates highest_price and returns SL from new HWM
rspec ./spec/services/trading/trailing_engine_spec.rb:113 # Trading::TrailingEngine with NIFTY instrument Phase 3: High Watermark Trailing after a pullback from high maintains SL from the peak
rspec ./spec/services/trading/trailing_engine_spec.rb:257 # Trading::TrailingEngine expiry-day tightening (Thursday) on Thursday morning applies expiry tightening (0.60x) combined with session factor (1.0x)
rspec ./spec/services/trading/trailing_engine_spec.rb:271 # Trading::TrailingEngine expiry-day tightening (Thursday) on Thursday afternoon applies double tightening (0.75x session × 0.60x expiry)
rspec ./spec/services/trading_session_spec.rb:10 # TradingSession::Service.market_closed? when market is closed (after 3:30 PM IST) returns true at exactly 3:30 PM IST
rspec ./spec/services/trading_session_spec.rb:16 # TradingSession::Service.market_closed? when market is closed (after 3:30 PM IST) returns true at 3:30:01 PM IST
rspec ./spec/services/trading_session_spec.rb:91 # TradingSession::Service.after_market_close_time? returns true at or after 15:30 IST
rspec ./spec/services/trading_session_spec.rb:122 # TradingSession::Service.entry_allowed? when before entry start time (9:20 AM) returns false with appropriate reason
rspec ./spec/services/trading_session_spec.rb:182 # TradingSession::Service.entry_allowed? when after entry end time (3:15 PM) returns false at 3:15 PM IST
rspec ./spec/services/trading_session_spec.rb:211 # TradingSession::Service.should_force_exit? when at or after exit deadline (3:15 PM) returns true at 3:15 PM IST
rspec ./spec/services/trading_session_spec.rb:244 # TradingSession::Service.seconds_until_session_end returns positive seconds before 3:15 PM
rspec ./spec/services/trading_session_spec.rb:252 # TradingSession::Service.seconds_until_session_end returns 0 at or after 3:15 PM
rspec ./spec/services/trading_system/position_heartbeat_market_close_spec.rb:36 # TradingSystem::PositionHeartbeat#start when market is closed but positions exist continues heartbeat operations
rspec ./spec/services/trading_system/signal_scheduler_spec.rb:57 # TradingSystem::SignalScheduler#perform_signal_scan when market is open performs signal scan by processing indices
rspec ./spec/smoke/lib_load_spec.rb:6 # Smoke: lib/ loads loads all lib Ruby source files
rspec ./spec/smoke/zeitwerk_eager_load_spec.rb:6 # Smoke: Zeitwerk eager load eager loads the application without errors
rspec ./spec/tasks/analysis_accuracy_spec.rb:87 # analysis:accuracy rake task log parsing patterns matches decision patterns correctly
rspec ./spec/tasks/analysis_accuracy_spec.rb:97 # analysis:accuracy rake task log parsing patterns extracts symbol from decision pattern

Coverage report generated for RSpec to /home/nemesis/project/trading-workspace/algo_scalper_api/coverage.
Line Coverage: 27.77% (8309 / 29923)
Stopped processing SimpleCov as a previous error not related to SimpleCov has been detected