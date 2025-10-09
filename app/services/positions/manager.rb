# frozen_string_literal: true

require "singleton"
require "concurrent/map"

module Positions
  class Manager
    include Singleton

    FILL_STATUSES = %w[TRADED COMPLETE PARTIAL].freeze
    CANCELLED_STATUSES = %w[CANCELLED REJECTED EXPIRED].freeze

    def initialize
      @order_index = Concurrent::Map.new
      @tracker_by_subscription = Concurrent::Map.new
      if defined?(Live::MarketFeedHub)
        Live::MarketFeedHub.instance.on_tick { |tick| handle_tick(tick) }
        Live::MarketFeedHub.instance.on_reconnected { refresh_all_subscriptions }
      end
    end

    def bootstrap!
      Live::WsHub.instance.start!
      preload_active_trackers
      sync_remote_positions
    end

    def handle_order_update(payload)
      order_no = (payload[:order_no] || payload[:order_id]).to_s
      return if order_no.blank?

      status = (payload[:order_status] || payload[:status]).to_s.upcase
      if FILL_STATUSES.include?(status)
        activate_tracker(order_no, payload)
      elsif CANCELLED_STATUSES.include?(status)
        cancel_tracker(order_no)
      end
    rescue StandardError => e
      Rails.logger.error("Positions::Manager update failed for #{order_no}: #{e.class} - #{e.message}")
    end

    def exit_position(tracker, reason:, exit_price: nil)
      tracker.with_lock do
        return unless tracker.active?

        attrs = exit_order_attributes(tracker)
        if attrs
          Rails.logger.info("Risk exit #{reason} for #{tracker.order_no} at #{exit_price}, placing #{attrs[:transaction_type]} order")
          Dhanhq.client.place_order(attrs)
        else
          Rails.logger.warn("Cannot derive exit order attributes for #{tracker.order_no}; skipping broker exit")
        end

        tracker.mark_exited!(price: exit_price, reason: reason.to_s)
        deregister_tracker(tracker)
      end
    rescue StandardError => e
      Rails.logger.error("Failed to exit position #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    private

    def activate_tracker(order_no, payload)
      tracker = upsert_tracker(order_no, payload)
      avg_price = payload[:average_traded_price] || payload[:average_price]
      quantity = payload[:filled_quantity] || payload[:traded_quantity] ||
                 payload[:quantity] || payload[:net_qty] || payload[:net_quantity]

      tracker.mark_active!(avg_price: avg_price, quantity: quantity)
      register_tracker(tracker)
      Orders::RiskManager.instance.register_tracker(tracker)
      subscribe_tracker(tracker)
    end

    def cancel_tracker(order_no)
      tracker = PositionTracker.find_by(order_no: order_no)
      return unless tracker

      tracker.mark_cancelled!
      deregister_tracker(tracker)
      Orders::RiskManager.instance.deregister_tracker(tracker)
    end

    def upsert_tracker(order_no, payload)
      tracker = PositionTracker.find_or_initialize_by(order_no: order_no)
      tracker.security_id ||= payload[:security_id].to_s.presence || payload[:securityId].to_s
      tracker.transaction_type ||= payload[:transaction_type] || payload[:transactionType]
      tracker.product_type ||= payload[:product_type] || payload[:productType]
      tracker.strategy ||= payload[:strategy] || default_strategy_for(payload, tracker)
      tracker.exchange_segment ||= payload[:exchange_segment] || payload[:segment]

      unless tracker.instrument
        tracker.instrument = find_instrument(tracker.security_id, tracker.exchange_segment)
      end

      tracker.save! if tracker.new_record? || tracker.changed?
      tracker
    end

    def find_instrument(security_id, segment)
      return if security_id.blank?

      if segment.present?
        Instrument.find_by(security_id: security_id.to_s, exchange_segment: segment.to_s)
      else
        Instrument.find_by(security_id: security_id.to_s)
      end
    rescue StandardError => e
      Rails.logger.warn("Instrument lookup failed for #{segment}:#{security_id} - #{e.message}")
      nil
    end

    def default_strategy_for(payload, tracker)
      segment = tracker.exchange_segment || payload[:exchange_segment]
      segment.to_s == "NSE_FNO" ? Orders::RiskManager::DEFAULT_RULE_KEY : nil
    rescue NameError
      nil
    end

    def register_tracker(tracker)
      segment = tracker.resolved_exchange_segment
      return unless segment && tracker.security_id

      key = subscription_key(segment, tracker.security_id)
      @order_index[tracker.order_no] = key
      @tracker_by_subscription[key] = tracker
    end

    def deregister_tracker(tracker)
      key = @order_index.delete(tracker.order_no)
      return unless key

      @tracker_by_subscription.delete(key)
      unsubscribe_if_unused(key)
      Orders::RiskManager.instance.deregister_tracker(tracker)
    end

    def subscribe_tracker(tracker)
      segment = tracker.resolved_exchange_segment
      return unless segment && tracker.security_id

      Live::WsHub.instance.subscribe_option!(segment: segment, security_id: tracker.security_id)
    end

    def unsubscribe_if_unused(key)
      return if @tracker_by_subscription.key?(key)

      segment, security_id = key.split(":", 2)
      Live::WsHub.instance.unsubscribe_option!(segment: segment, security_id: security_id)
    end

    def preload_active_trackers
      PositionTracker.active.includes(:instrument).find_each do |tracker|
        register_tracker(tracker)
        subscribe_tracker(tracker)
        Orders::RiskManager.instance.register_tracker(tracker)
      end
    rescue ActiveRecord::StatementInvalid
      Rails.logger.warn("Position trackers table not present yet; skipping preload")
    end

    def sync_remote_positions
      positions = Dhanhq.client.active_positions
      positions.each do |position|
        payload = normalize_payload(position)
        next if payload[:security_id].blank?

        order_no = payload[:order_no] || payload[:position_id] || "POS-#{payload[:security_id]}"
        activate_tracker(order_no, payload)
      end
    rescue Dhanhq::Client::Error => e
      Rails.logger.warn("Skipping broker position sync: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("Unexpected error while syncing broker positions: #{e.class} - #{e.message}")
    end

    def normalize_payload(source)
      return source if source.is_a?(Hash) && source.keys.any? { |k| k.is_a?(Symbol) }

      hash = source.respond_to?(:to_h) ? source.to_h : source
      return {} unless hash

      hash.each_with_object({}) do |(key, value), memo|
        memo[key.to_s.underscore.to_sym] = value
      end
    end

    def exit_order_attributes(tracker)
      segment = tracker.resolved_exchange_segment
      quantity = tracker.quantity
      return if segment.blank? || tracker.security_id.blank? || quantity.to_i.zero?

      txn = tracker.buy? ? "SELL" : "BUY"
      {
        exchange_segment: segment,
        security_id: tracker.security_id,
        order_type: "MARKET",
        validity: "DAY",
        transaction_type: txn,
        product_type: tracker.product_type || "INTRADAY",
        quantity: quantity
      }
    end

    def handle_tick(tick)
      key = subscription_key(tick[:segment], tick[:security_id])
      tracker = @tracker_by_subscription[key]
      return unless tracker&.active?

      Orders::RiskManager.instance.evaluate!(tracker: tracker, tick: tick)
    end

    def refresh_all_subscriptions
      @tracker_by_subscription.each_value do |tracker|
        subscribe_tracker(tracker)
      end
    end

    def subscription_key(segment, security_id)
      "#{segment}:#{security_id}"
    end
  end
end
