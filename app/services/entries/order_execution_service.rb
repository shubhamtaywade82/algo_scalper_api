# frozen_string_literal: true

module Entries
  class OrderExecutionService
    def self.call(context)
      new(context).call
    end

    def initialize(context)
      @context = context
      @index_cfg = context[:index_cfg]
      @pick = context[:pick]
      @instrument = context[:instrument]
      @side = context[:side]
      @quantity = context[:quantity]
      @ltp = context[:ltp]
      @entry_metadata = context[:entry_metadata]
      @bos_context = context[:bos_context]
      @signal = context[:signal]
    end

    def call
      place_cmd = Orders::Commands::PlaceOrderCommand.new(
        gateway: Orders.config.gateway,
        side: :buy,
        segment: @pick[:segment] || @index_cfg[:segment],
        security_id: @pick[:security_id],
        qty: @quantity,
        meta: {
          client_order_id: build_client_order_id,
          ltp: @ltp,
          price: @ltp,
          symbol: @pick[:symbol]
        }
      ).call

      return failure(place_cmd.reason) unless place_cmd.success?

      response = place_cmd.payload[:raw] || {}
      order_no = extract_order_no(response)
      return failure('order_no_missing') unless order_no

      tracker = create_tracker(response, order_no)
      return failure('tracker_creation_failed') unless tracker

      mark_bos_consumed! if @bos_context
      tracker
    end

    private

    def build_client_order_id
      Entries::EntryGuard.build_client_order_id(index_cfg: @index_cfg, pick: @pick, signal: @signal)
    end

    def extract_order_no(response)
      Entries::EntryGuard.extract_order_no(response)
    end

    def create_tracker(response, order_no)
      if response.is_a?(Hash) && response[:paper]
        Entries::EntryGuard.create_paper_tracker!(
          instrument: @instrument, pick: @pick, side: @side, quantity: @quantity,
          index_cfg: @index_cfg, ltp: @ltp, order_no: order_no,
          entry_metadata: @entry_metadata, bos_context: @bos_context
        )
      else
        Entries::EntryGuard.create_tracker!(
          instrument: @instrument, order_no: order_no, pick: @pick, side: @side,
          quantity: @quantity, index_cfg: @index_cfg, ltp: @ltp,
          entry_metadata: @entry_metadata, bos_context: @bos_context
        )
      end
    end

    def mark_bos_consumed!
      Rails.cache.write(
        "bos:consumed:#{@index_cfg[:key]}:#{@bos_context[:bos_id]}",
        true,
        expires_in: 1.day
      )
    end

    def failure(reason)
      { error: reason }
    end
  end
end
