# frozen_string_literal: true

require 'securerandom'

module Orders
  # Executes multi-leg option orders (e.g. credit spreads, debit spreads).
  # Enforces hedge-first sequencing (BUY hedge first, SELL short second) to avoid naked short exposure.
  # Executes rollback (closes filled legs) immediately upon any subsequent leg failure.
  class MultiLegExecutor
    attr_reader :legs, :group_id, :mode

    def self.execute(legs:, group_id: nil, mode: nil)
      new(legs: legs, group_id: group_id, mode: mode).call
    end

    def initialize(legs:, group_id: nil, mode: nil)
      @legs = Array(legs)
      @group_id = group_id || "ML_#{SecureRandom.hex(6).upcase}"
      @mode = (mode || (AlgoConfig.fetch.dig(:paper_trading, :enabled) ? :paper : :live)).to_sym
    end

    def call
      return failure('no legs provided') if legs.blank?

      sorted_legs = legs.sort_by { |l| l[:leg_order] || leg_order_for(l[:type]) }
      filled_legs = []

      sorted_legs.each_with_index do |leg, idx|
        leg_coid = "#{group_id}_L#{idx + 1}"
        result = place_leg(leg, leg_coid)

        if result.nil? || (result.is_a?(Hash) && result[:success] == false)
          rollback_filled!(filled_legs, idx + 1, sorted_legs.size, 'placement failed')
          return failure("leg #{idx + 1} placement failed", rolled_back: true)
        end

        fill = wait_for_fill(result, leg_coid, idx + 1)

        if fill[:failed]
          cancel_order(leg_coid)
          rollback_filled!(filled_legs, idx + 1, sorted_legs.size, fill[:error])
          return failure("leg #{idx + 1} fill failed: #{fill[:error]}", rolled_back: true)
        end

        filled_legs << { leg: leg, result: fill, coid: leg_coid }
        Rails.logger.info(
          "[MultiLegExecutor] Leg #{idx + 1}/#{sorted_legs.size} filled: #{leg[:type]} " \
          "#{leg[:strike]} @ #{fill[:fill_price]}"
        )
      end

      success(filled_legs)
    rescue StandardError => e
      Rails.logger.error("[MultiLegExecutor] #{e.class}: #{e.message}")
      rollback_filled!(filled_legs, 0, sorted_legs&.size || 0, e.message)
      failure(e.message, rolled_back: true)
    end

    private

    # BUY hedge FIRST (defines risk), SELL short SECOND (collects premium)
    def leg_order_for(type)
      case type.to_s.to_sym
      when :long_put, :long_call then 1
      when :short_put, :short_call then 2
      else 1
      end
    end

    def place_leg(leg, leg_coid)
      if paper_mode?
        place_paper_leg(leg, leg_coid)
      else
        place_live_leg(leg, leg_coid)
      end
    end

    def place_paper_leg(leg, leg_coid)
      gateway = Orders::GatewayFactory.selected_gateway
      action = leg[:action].to_s.downcase

      gateway.place_market(
        side: action.upcase,
        segment: leg[:segment] || 'NSE_FNO',
        security_id: leg[:security_id],
        qty: leg[:quantity],
        meta: { client_order_id: leg_coid }
      )
    end

    def place_live_leg(leg, leg_coid)
      action = leg[:action].to_s.downcase

      if action == 'buy'
        Orders::Placer.buy_market!(
          seg: leg[:segment] || 'NSE_FNO',
          sid: leg[:security_id],
          qty: leg[:quantity],
          client_order_id: leg_coid,
          product_type: leg[:product_type] || 'INTRADAY'
        )
      else
        Orders::Placer.sell_market!(
          seg: leg[:segment] || 'NSE_FNO',
          sid: leg[:security_id],
          qty: leg[:quantity],
          client_order_id: leg_coid,
          product_type: leg[:product_type] || 'INTRADAY'
        )
      end
    end

    def wait_for_fill(order_result, coid, _leg_idx)
      if paper_mode?
        price = order_result[:fill_price] || fallback_ltp(coid) || 100.0
        return { success: true, fill_price: price.to_f, fill_quantity: 1, order_id: coid }
      end

      timeout = 15
      poll_interval = 1
      elapsed = 0

      while elapsed < timeout
        status = Orders::Placer.fetch_position_details(coid)

        case status&.dig(:orderStatus)
        when 'TRADED'
          return {
            success: true,
            fill_price: status[:tradedPrice].to_f,
            fill_quantity: status[:tradedQty].to_i,
            order_id: status[:orderId]
          }
        when 'REJECTED', 'CANCELLED'
          return { failed: true, error: "Order #{status[:orderStatus]}" }
        end

        sleep(poll_interval)
        elapsed += poll_interval
      end

      { failed: true, error: "Fill timeout after #{timeout}s" }
    end

    def cancel_order(coid)
      Orders::GatewayFactory.selected_gateway.cancel_order(coid)
    rescue StandardError => e
      Rails.logger.warn("[MultiLegExecutor] Cancel failed for #{coid}: #{e.message}")
    end

    def rollback_filled!(filled_legs, failed_idx, total, reason)
      return if filled_legs.blank?

      Rails.logger.error(
        "[MultiLegExecutor] ROLLBACK #{group_id}: leg #{failed_idx}/#{total} failed (#{reason}) — " \
        "closing #{filled_legs.size} filled legs"
      )

      filled_legs.each do |filled|
        leg = filled[:leg]
        close_action = leg[:action].to_s.downcase == 'buy' ? 'sell' : 'buy'
        close_coid = "#{group_id}_RB_#{leg[:strike]}_#{leg[:type]}"
        qty = filled.dig(:result, :fill_quantity) || leg[:quantity]

        execute_rollback_leg(leg, close_action, close_coid, qty)
      end
    end

    def execute_rollback_leg(leg, close_action, close_coid, qty)
      if paper_mode?
        Orders::GatewayFactory.selected_gateway.place_market(
          side: close_action.upcase,
          segment: leg[:segment] || 'NSE_FNO',
          security_id: leg[:security_id],
          qty: qty,
          meta: { client_order_id: close_coid }
        )
      elsif close_action == 'sell'
        Orders::Placer.sell_market!(
          seg: leg[:segment] || 'NSE_FNO',
          sid: leg[:security_id],
          qty: qty,
          client_order_id: close_coid,
          product_type: leg[:product_type] || 'INTRADAY'
        )
      else
        Orders::Placer.buy_market!(
          seg: leg[:segment] || 'NSE_FNO',
          sid: leg[:security_id],
          qty: qty,
          client_order_id: close_coid,
          product_type: leg[:product_type] || 'INTRADAY'
        )
      end
      Rails.logger.info("[MultiLegExecutor] Rolled back #{leg[:action]} #{leg[:type]} #{leg[:strike]}")
    rescue StandardError => e
      Rails.logger.error("[MultiLegExecutor] ROLLBACK FAILED: #{leg[:type]} #{leg[:strike]} — #{e.message}")
      Notifications::TelegramNotifier.instance.notify_error(
        "🚨 ROLLBACK FAILED for #{group_id}: #{leg[:type]} #{leg[:strike]} — MANUAL INTERVENTION REQUIRED",
        context: 'MultiLegExecutor'
      )
    end

    def fallback_ltp(coid)
      tracker = PositionTracker.find_by(client_order_id: coid)
      tracker&.entry_price&.to_f
    end

    def paper_mode?
      mode == :paper
    end

    def success(filled_legs)
      { success: true, group_id: group_id, legs: filled_legs }
    end

    def failure(error, rolled_back: false)
      { success: false, group_id: group_id, error: error, rolled_back: rolled_back }
    end
  end
end
