# frozen_string_literal: true

require "digest"
require "timeout"
require "token_bucket"

module Orders
  class Placer
    # Valid tradable segments per DhanHQ API documentation
    # Indices (IDX_I, BSE_IDX, NSE_IDX) are NOT tradable - they are reference values only
    # NSE: NSE_EQ (Equity Cash), NSE_FNO (Futures & Options), NSE_CURRENCY (Currency)
    # BSE: BSE_EQ (Equity Cash), BSE_FNO (Futures & Options), BSE_CURRENCY (Currency)
    # MCX: MCX_COMM (Commodity)
    VALID_TRADABLE_SEGMENTS = %w[
      NSE_EQ
      NSE_FNO
      NSE_CURRENCY
      BSE_EQ
      BSE_FNO
      BSE_CURRENCY
      MCX_COMM
    ].freeze

    class << self
      def buy_market!(seg:, sid:, qty:, client_order_id:, product_type: "INTRADAY", price: nil,
                      target_price: nil, stop_loss_price: nil, trailing_jump: nil)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        order = nil
        begin
          unless seg && sid && qty && normalized_id
            Rails.logger.error("[Orders::Placer] Missing required parameters for buy_market!: seg=#{seg}, sid=#{sid}, qty=#{qty}, client_order_id=#{client_order_id}")
            return nil
          end

          unless segment_tradable?(seg)
            Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
            return nil
          end

          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::BUY,
            exchange_segment: seg,
            security_id: sid.to_s,
            quantity: qty.to_i,
            order_type: DhanHQ::Constants::OrderType::MARKET,
            product_type: product_type,
            validity: DhanHQ::Constants::Validity::DAY,
            correlation_id: normalized_id,
            disclosed_quantity: 0
          }
          # DhanHQ 2.6.x PlaceOrderContract: MARKET orders must not send price
          payload[:bo_profit_value] = target_price if target_price.present?
          payload[:bo_stop_loss_value] = stop_loss_price if stop_loss_price.present?

          Rails.logger.info("[Orders::Placer] BUY payload: #{payload.inspect}")

          if order_placement_enabled?
            order = with_token_auto_heal(context: 'orders.buy_market') do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] BUY response: #{order.inspect}") if order
          else
            Rails.logger.warn('[Orders::Placer] BUY blocked because PLACE_ORDER is not enabled')
          end
          order
        ensure
          # DhanHQ dedupes by correlation_id, so releasing the claim on failure lets a
          # legitimate retry reuse the same client_order_id instead of permanently
          # burning it for 20 minutes (previously: any failure — even one where the
          # broker was never reached — blocked every subsequent attempt).
          release_claim!(normalized_id) if order.nil?
        end
      end

      def sell_market!(seg:, sid:, qty:, client_order_id:, product_type: nil)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        unless seg && sid && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_market!: seg=#{seg}, sid=#{sid}, client_order_id=#{client_order_id}")
          release_claim!(normalized_id) # nothing was sent to the broker; safe to allow an immediate retry
          return nil
        end

        position = fetch_position_details(sid)
        actual_segment = position ? position[:exchange_segment] : seg

        unless segment_tradable?(actual_segment)
          Rails.logger.error("[Orders::Placer] Segment #{actual_segment} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
          release_claim!(normalized_id)
          return nil
        end

        actual_qty = if position && position[:net_qty].to_i.positive?
                       position[:net_qty]
                     else
          qty
                     end

        # place_order_with_slicing releases the claim! on a clean single-slice failure
        # (nothing reached the broker) but leaves it claimed once a slice has partially
        # filled — see its docstring.
        place_order_with_slicing(sid: sid, qty: actual_qty, client_order_id: normalized_id) do |slice_qty, slice_coid|
          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::SELL,
            exchange_segment: position ? position[:exchange_segment] : seg,
            security_id: sid.to_s,
            quantity: slice_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::MARKET,
            product_type: position ? position[:product_type] : product_type,
            validity: DhanHQ::Constants::Validity::DAY,
            disclosed_quantity: 0,
            correlation_id: slice_coid
          }

          Rails.logger.info("[Orders::Placer] SELL payload: #{payload.inspect}")

          if order_placement_enabled?
            slice_order = with_token_auto_heal(context: "orders.sell_market") do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] SELL response: #{slice_order.inspect}") if slice_order
            slice_order
          else
            Rails.logger.warn("[Orders::Placer] SELL blocked because PLACE_ORDER is not enabled")
            OpenStruct.new(order_id: "MOCK_MARKET_#{SecureRandom.hex(4).upcase}", status: "success")
          end
        end
      end

      def buy_ioc_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for buy_ioc_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          release_claim!(normalized_id)
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          release_claim!(normalized_id)
          return nil
        end

        place_order_with_slicing(sid: sid, qty: qty, client_order_id: normalized_id) do |slice_qty, slice_coid|
          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::BUY,
            exchange_segment: seg,
            security_id: sid.to_s,
            quantity: slice_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::LIMIT,
            product_type: product_type,
            price: price.to_f.round(2),
            validity: DhanHQ::Constants::Validity::IOC,
            correlation_id: slice_coid,
            disclosed_quantity: 0
          }

          Rails.logger.info("[Orders::Placer] BUY IOC LIMIT payload: #{payload.inspect}")

          if order_placement_enabled?
            slice_order = with_token_auto_heal(context: "orders.buy_ioc_limit") do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] BUY IOC LIMIT response: #{slice_order.inspect}") if slice_order
            slice_order
          else
            Rails.logger.warn("[Orders::Placer] BUY IOC LIMIT blocked because PLACE_ORDER is not enabled")
            OpenStruct.new(order_id: "MOCK_IOC_#{SecureRandom.hex(4).upcase}", status: "success")
          end
        end
      end

      # Market order first; fall back to IOC limit if market returns nil (e.g. PLACE_ORDER disabled
      # or broker rejected). This keeps the entry pipeline resilient without changing live code paths.
      def buy_entry_with_fallback!(seg:, sid:, qty:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless seg && sid && qty && normalized_id

        order = buy_market!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
        return order if order

        Rails.logger.warn("[Orders::Placer] buy_market! returned nil for #{sid}; falling back to IOC limit")
        buy_ioc_limit!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
      rescue StandardError => e
        Rails.logger.warn("[Orders::Placer] buy_entry_with_fallback! market failed (#{e.class}); trying IOC limit")
        buy_ioc_limit!(seg: seg, sid: sid, qty: qty, client_order_id: normalized_id, product_type: product_type)
      end

      def sell_ioc_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_ioc_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          release_claim!(normalized_id)
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          release_claim!(normalized_id)
          return nil
        end

        place_order_with_slicing(sid: sid, qty: qty, client_order_id: normalized_id) do |slice_qty, slice_coid|
          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::SELL,
            exchange_segment: seg,
            security_id: sid.to_s,
            quantity: slice_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::LIMIT,
            product_type: product_type,
            price: price.to_f.round(2),
            validity: DhanHQ::Constants::Validity::IOC,
            correlation_id: slice_coid,
            disclosed_quantity: 0
          }

          Rails.logger.info("[Orders::Placer] SELL IOC LIMIT payload: #{payload.inspect}")

          if order_placement_enabled?
            slice_order = with_token_auto_heal(context: "orders.sell_ioc_limit") do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] SELL IOC LIMIT response: #{slice_order.inspect}") if slice_order
            slice_order
          else
            Rails.logger.warn("[Orders::Placer] SELL IOC LIMIT blocked because PLACE_ORDER is not enabled")
            OpenStruct.new(order_id: "MOCK_IOC_#{SecureRandom.hex(4).upcase}", status: "success")
          end
        end
      end

      def sell_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for sell_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          release_claim!(normalized_id)
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          release_claim!(normalized_id)
          return nil
        end

        place_order_with_slicing(sid: sid, qty: qty, client_order_id: normalized_id) do |slice_qty, slice_coid|
          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::SELL,
            exchange_segment: seg,
            security_id: sid.to_s,
            quantity: slice_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::LIMIT,
            product_type: product_type,
            price: price.to_f.round(2),
            validity: DhanHQ::Constants::Validity::DAY,
            correlation_id: slice_coid,
            disclosed_quantity: 0
          }

          Rails.logger.info("[Orders::Placer] SELL LIMIT payload: #{payload.inspect}")

          if order_placement_enabled?
            slice_order = with_token_auto_heal(context: "orders.sell_limit") do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] SELL LIMIT response: #{slice_order.inspect}") if slice_order
            slice_order
          else
            Rails.logger.warn("[Orders::Placer] SELL LIMIT blocked because PLACE_ORDER is not enabled")
            OpenStruct.new(order_id: "MOCK_LIMIT_#{SecureRandom.hex(4).upcase}", status: "success")
          end
        end
      end

      def buy_limit!(seg:, sid:, qty:, price:, client_order_id:, product_type: "NORMAL")
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        unless seg && sid && qty && price && normalized_id
          Rails.logger.error("[Orders::Placer] Missing required parameters for buy_limit!: seg=#{seg}, sid=#{sid}, qty=#{qty}, price=#{price}, client_order_id=#{client_order_id}")
          release_claim!(normalized_id)
          return nil
        end

        unless segment_tradable?(seg)
          Rails.logger.error("[Orders::Placer] Segment #{seg} is not tradable.")
          release_claim!(normalized_id)
          return nil
        end

        place_order_with_slicing(sid: sid, qty: qty, client_order_id: normalized_id) do |slice_qty, slice_coid|
          payload = {
            transaction_type: DhanHQ::Constants::TransactionType::BUY,
            exchange_segment: seg,
            security_id: sid.to_s,
            quantity: slice_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::LIMIT,
            product_type: product_type,
            price: price.to_f.round(2),
            validity: DhanHQ::Constants::Validity::DAY,
            correlation_id: slice_coid,
            disclosed_quantity: 0
          }

          Rails.logger.info("[Orders::Placer] BUY LIMIT payload: #{payload.inspect}")

          if order_placement_enabled?
            slice_order = with_token_auto_heal(context: "orders.buy_limit") do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] BUY LIMIT response: #{slice_order.inspect}") if slice_order
            slice_order
          else
            Rails.logger.warn("[Orders::Placer] BUY LIMIT blocked because PLACE_ORDER is not enabled")
            OpenStruct.new(order_id: "MOCK_LIMIT_#{SecureRandom.hex(4).upcase}", status: "success")
          end
        end
      end

      def exit_position!(seg:, sid:, client_order_id:)
        normalized_id = normalize_client_order_id(client_order_id)
        return nil unless claim!(normalized_id)

        order = nil
        begin
          unless sid && normalized_id
            Rails.logger.error("[Orders::Placer] Missing required parameters for exit_position!: sid=#{sid}, client_order_id=#{client_order_id}")
            return nil
          end

          position_details = fetch_position_details(sid)
          unless position_details
            Rails.logger.error("[Orders::Placer] Cannot find position to exit for sid=#{sid}")
            return nil
          end

          actual_qty = position_details[:net_qty]
          actual_segment = position_details[:exchange_segment]
          position_type = position_details[:position_type]

          unless segment_tradable?(actual_segment)
            Rails.logger.error("[Orders::Placer] Segment #{actual_segment} is not tradable. Valid segments: #{VALID_TRADABLE_SEGMENTS.join(', ')}")
            return nil
          end

          transaction_type = case position_type
                             when "LONG" then "SELL"
                             when "SHORT" then "BUY"
                             else
            Rails.logger.error("[Orders::Placer] Unknown position type #{position_type}")
            return nil
                             end

          payload = {
            transaction_type: transaction_type,
            exchange_segment: actual_segment,
            security_id: sid.to_s,
            quantity: actual_qty.to_i,
            order_type: DhanHQ::Constants::OrderType::MARKET,
            product_type: position_details[:product_type],
            validity: DhanHQ::Constants::Validity::DAY,
            disclosed_quantity: 0,
            correlation_id: normalized_id
          }

          Rails.logger.info("[Orders::Placer] EXIT payload: #{payload.inspect}")

          if order_placement_enabled?
            order = with_token_auto_heal(context: 'orders.exit_position') do
              DhanHQ::Models::Order.create!(payload)
            end
            Rails.logger.info("[Orders::Placer] EXIT response: #{order.inspect}") if order
          else
            Rails.logger.warn('[Orders::Placer] EXIT blocked because PLACE_ORDER is not enabled')
          end

          order
        ensure
          # Exits are the most safety-critical path here: a released claim means the
          # 5s enforcement loop's next retry (or reconciliation's stuck-exit repair)
          # isn't blocked by our own 20-minute idempotency guard for a request that
          # never actually reached the broker (or failed before any fill).
          release_claim!(normalized_id) if order.nil?
        end
      end

      private

      def fetch_position_details(security_id)
        positions = DhanHQ::Models::Position.active
        pos = positions.find { |p| p.security_id.to_s == security_id.to_s }
        return nil unless pos

        {
          product_type: pos.respond_to?(:product_type) ? pos.product_type : pos[:product_type],
          net_qty: pos.respond_to?(:net_qty) ? pos.net_qty.to_i : (pos[:net_qty] || pos[:quantity]).to_i,
          exchange_segment: pos.respond_to?(:exchange_segment) ? pos.exchange_segment : pos[:exchange_segment],
          position_type: pos.respond_to?(:position_type) ? pos.position_type : (pos[:position_type] || "LONG"),
          buy_avg: pos.respond_to?(:buy_avg) ? pos.buy_avg : nil,
          trading_symbol: pos.respond_to?(:trading_symbol) ? pos.trading_symbol : pos[:trading_symbol]
        }
      rescue StandardError => e
        Rails.logger.error("[Orders::Placer] fetch_position_details error: #{e.class} - #{e.message}")
        nil
      end

      # Self-imposed rate limit (not a broker rejection) — worth a short bounded wait
      # rather than silently dropping a live entry/exit order. At 10 tokens/sec, a
      # 150ms wait typically frees a token; 5 attempts caps the total wait at ~750ms.
      RATE_LIMIT_MAX_WAIT_ATTEMPTS = 5
      RATE_LIMIT_WAIT_SECONDS = 0.15

      def with_order_rate_limit(context: nil, &)
        attempts = 0
        begin
          rate_limiter.consume!(&)
        rescue Orders::TokenBucket::RateLimited => e
          attempts += 1
          if attempts <= RATE_LIMIT_MAX_WAIT_ATTEMPTS
            Rails.logger.warn("[Orders::Placer] rate limited (#{context}), waiting to retry (attempt #{attempts}): #{e.message}")
            sleep RATE_LIMIT_WAIT_SECONDS
            retry
          end

          Rails.logger.error("[Orders::Placer] rate limit still exceeded after #{attempts - 1} wait attempts (#{context}), giving up: #{e.message}")
          nil
        end
      end

      def rate_limiter
        # NOTE: this is Orders::TokenBucket (below in this namespace), not the unrelated
        # ::TokenBucket in lib/token_bucket.rb — that file is loaded by the require above
        # but shadowed by lexical scoping and never actually used. Referenced explicitly
        # here to avoid relying on that shadowing.
        @rate_limiter ||= Orders::TokenBucket.new(rate: 10, per: 1.second)
      end

      RETRYABLE_ERROR_CLASSES = [Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT].freeze

      def with_token_auto_heal(context:, &)
        retried = false
        begin
          result = with_order_rate_limit(context: context, &)
          reset_consecutive_order_failures! if result
          result
        rescue StandardError => e
          Rails.logger.error("[Orders::Placer] #{context} failed: #{e.class} - #{e.message}")

          unless DhanhqErrorHandler.token_expired?(e)
            record_order_failure!
            # Previously every error was swallowed to nil here, so GatewayLive#with_retries
            # (which wraps buy_market!/sell_market!) never saw an exception to retry on.
            # Network/timeout errors are re-raised so that retry logic actually engages;
            # everything else (validation, broker rejection) still returns nil as before.
            raise e if RETRYABLE_ERROR_CLASSES.any? { |klass| e.is_a?(klass) }

            return nil
          end

          if retried
            Rails.logger.error("[Orders::Placer] #{context} retry failed: #{e.class} - #{e.message}")
            record_order_failure!
            return nil
          end

          Rails.logger.warn("[Orders::Placer] #{context} unauthorized; refreshing token and retrying once")
          Dhan::TokenManager.refresh! if defined?(Dhan::TokenManager)
          retried = true
          retry
        end
      end

      CONSECUTIVE_FAILURES_CACHE_KEY = 'orders:placer:consecutive_failures'
      CONSECUTIVE_FAILURES_TTL = 15.minutes

      # Auto-trips Risk::CircuitBreaker after N consecutive broker failures — previously the
      # breaker only tripped via manual API call, so a broker outage or bad payload could burn
      # through repeated failed orders with nothing halting entries. Rate-limited/dry-run "nil"
      # results don't reach here (they don't raise), so only real broker failures count.
      def record_order_failure!
        threshold = auto_trip_threshold
        return unless threshold&.positive?

        count = (Rails.cache.read(CONSECUTIVE_FAILURES_CACHE_KEY) || 0) + 1
        Rails.cache.write(CONSECUTIVE_FAILURES_CACHE_KEY, count, expires_in: CONSECUTIVE_FAILURES_TTL)
        return unless count >= threshold

        Risk::CircuitBreaker.instance.trip!(reason: "auto: #{count} consecutive order failures")
        Rails.cache.delete(CONSECUTIVE_FAILURES_CACHE_KEY)
      end

      def reset_consecutive_order_failures!
        Rails.cache.delete(CONSECUTIVE_FAILURES_CACHE_KEY)
      end

      def auto_trip_threshold
        AlgoConfig.fetch.dig(:risk, :circuit_breaker_auto_trip_threshold) || 3
      rescue StandardError
        3
      end

      def order_placement_enabled?
        ENV['PLACE_ORDER'].to_s.casecmp('true').zero?
      end

      # Atomic check-and-set: the previous duplicate?/remember pair only recorded the id in
      # `ensure`, *after* the broker call, leaving a window where two concurrent calls with the
      # same client_order_id could both pass `duplicate?` before either registered. Claiming the
      # id up front via `unless_exist` closes that race — first caller gets true, the rest false.
      def claim!(client_order_id)
        return true if client_order_id.blank?

        Rails.cache.write("coid:#{client_order_id}", true, expires_in: 20.minutes, unless_exist: true)
      end

      # Releases a claim taken by claim! so a legitimate retry can reuse the same
      # client_order_id. Only call this when the attempt is known not to have reached
      # a state where re-sending it risks a duplicate the broker wouldn't itself dedupe
      # (DhanHQ dedupes by correlation_id — see claim! above).
      def release_claim!(client_order_id)
        return if client_order_id.blank?

        Rails.cache.delete("coid:#{client_order_id}")
      end

      def normalize_client_order_id(client_order_id)
        return if client_order_id.blank?

        value = client_order_id.to_s.strip
        return if value.blank?
        return value if value.length <= 30

        digest = Digest::SHA1.hexdigest(value)[0, 6]
        base = value[0, 23]
        "#{base}-#{digest}"
      end

      # Shared by sell_market!/buy_ioc_limit!/sell_ioc_limit!/sell_limit!/buy_limit! — all
      # of them call claim! before this and must have it released on a failed attempt, the
      # same way buy_market!/exit_position! do via their own ensure blocks. Releases only
      # when NO slice reached the broker (filled_qty still 0): once an earlier slice has
      # succeeded, a from-scratch resend under the same client_order_id would re-attempt
      # already-placed slices, so that case is intentionally left claimed for manual
      # reconciliation (see alert_partial_slice_failure).
      def place_order_with_slicing(sid:, qty:, client_order_id:, &block)
        index_key = resolve_index_key(sid)
        slices = Slicer.slice_quantity(index_key: index_key, total_quantity: qty)

        if slices.size <= 1
          result = nil
          begin
            result = yield(qty, client_order_id)
          ensure
            release_claim!(client_order_id) if result.nil?
          end
          return result
        end

        Rails.logger.info("[Orders::Placer] Slicing quantity #{qty} into #{slices.inspect} for index=#{index_key} (limit=#{Slicer.freeze_limit_for(index_key)})")

        last_order = nil
        filled_qty = 0
        begin
          slices.each_with_index do |slice_qty, index|
            slice_coid = "#{client_order_id}_#{index + 1}"

            # Sleep between slices (except first)
            sleep(Slicer.delay_seconds) if index.positive?

            last_order = yield(slice_qty, slice_coid)

            if last_order.nil?
              alert_partial_slice_failure(
                client_order_id: client_order_id,
                filled_qty: filled_qty,
                total_qty: qty,
                failed_slice_number: index + 1,
                total_slices: slices.size
              )
              break
            end

            filled_qty += slice_qty
          end

          last_order
        ensure
          release_claim!(client_order_id) if last_order.nil? && filled_qty.zero?
        end
      end

      def alert_partial_slice_failure(client_order_id:, filled_qty:, total_qty:, failed_slice_number:, total_slices:)
        message = "[Orders::Placer] Slice #{failed_slice_number}/#{total_slices} failed for #{client_order_id}: " \
                  "filled #{filled_qty}/#{total_qty} before failure — position is PARTIAL, no further slices will be sent"
        Rails.logger.error(message)
        Notifications::TelegramNotifier.instance.notify_error(message, context: 'Orders::Placer#place_order_with_slicing')
      rescue StandardError => e
        Rails.logger.error("[Orders::Placer] alert_partial_slice_failure failed: #{e.message}")
      end

      def resolve_index_key(sid)
        instrument = Instrument.find_by(security_id: sid.to_s)
        instrument&.underlying_symbol || 'default'
      rescue StandardError
        'default'
      end

      def segment_tradable?(segment)
        return false if segment.blank?

        VALID_TRADABLE_SEGMENTS.include?(segment.to_s.upcase)
      end
    end
  end
end
