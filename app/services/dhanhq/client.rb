# frozen_string_literal: true

require "singleton"

module Dhanhq
  class Client
    Error = Class.new(StandardError)

    attr_reader :logger

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def enabled?
      config&.enabled
    end

    def ensure_enabled!
      return if enabled?

      raise Error, "DhanHQ integration is disabled. Set DHANHQ_ENABLED=true to enable."
    end

    def place_order(attributes)
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Order.place(attributes) }
    end

    def create_order(attributes)
      ensure_enabled!
      wrap_errors(__method__) do
        order = DhanHQ::Models::Order.new(attributes)
        unless order.save
          message = order.respond_to?(:errors) ? order.errors.full_messages.to_sentence : "Unknown validation error"
          raise Error, "Order validation failed: #{message}"
        end
        order
      end
    end

    def modify_order(order_id:, **attributes)
      ensure_enabled!
      wrap_errors(__method__) do
        order = DhanHQ::Models::Order.find(order_id)
        order.modify(attributes)
        order
      end
    end

    def cancel_order(order_id:)
      ensure_enabled!
      wrap_errors(__method__) do
        order = DhanHQ::Models::Order.find(order_id)
        order.cancel
      end
    end

    def order(order_id)
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Order.find(order_id) }
    end

    def positions
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Position.all }
    end

    def holdings
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Holding.all }
    end

    def funds
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Funds.fetch }
    end

    def option_chain(underlying_scrip:, underlying_seg:, expiry: nil)
      ensure_enabled!
      wrap_errors(__method__) do
        payload = { underlying_scrip: underlying_scrip, underlying_seg: underlying_seg }
        if expiry
          DhanHQ::Models::OptionChain.fetch(**payload.merge(expiry: expiry))
        else
          DhanHQ::Models::OptionChain.fetch_expiry_list(**payload)
        end
      end
    end

    def historical_intraday(**params)
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::HistoricalData.intraday(**params) }
    end

    def historical_daily(**params)
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::HistoricalData.daily(**params) }
    end

    def trade_book
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Trade.today }
    end

    def profile
      ensure_enabled!
      wrap_errors(__method__) { DhanHQ::Models::Profile.fetch }
    end

    private

    def config
      Rails.application.config.x.dhanhq
    end

    def wrap_errors(action)
      yield
    rescue DhanHQ::Error => e
      logger.error("DhanHQ #{action} failed: #{e.message}")
      raise Error, e.message, e.backtrace
    rescue StandardError => e
      logger.error("Unexpected DhanHQ error during #{action}: #{e.class} - #{e.message}")
      raise Error, "Unexpected DhanHQ error: #{e.message}", e.backtrace
    end
  end

  class SharedClient
    include Singleton

    def self.instance
      super.tap(&:ensure_enabled!)
    end

    def method_missing(method_name, *args, **kwargs, &block)
      client.public_send(method_name, *args, **kwargs, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      client.respond_to?(method_name, include_private)
    end

    private

    def client
      @client ||= Client.new
    end
  end

  module_function

  def client
    SharedClient.instance
  end
end
