# frozen_string_literal: true

module Live
  # Compares local trading state against DhanHQ broker state.
  # Detects discrepancies in orders, positions, and funds.
  # Triggers circuit breaker on critical mismatches.
  #
  # PRD §46-47: Every 30-60s, reconciliation loop compares
  # broker state with local state. Critical discrepancies halt trading.
  class BrokerReconciliationService
    INTERVAL = 60.seconds

    def initialize(client: nil)
      @client = client || build_client
    end

    def reconcile!
      run = ReconciliationRun.create!(
        status: 'running',
        mode: current_mode,
        started_at: Time.current
      )

      results = {
        orders: reconcile_orders(run),
        positions: reconcile_positions(run),
        funds: reconcile_funds(run)
      }

      finalize_run(run, results)
    rescue StandardError => e
      run&.update(status: 'error', summary: { error: e.message })
      Rails.logger.error("[BrokerRecon] Failed: #{e.class} - #{e.message}")
      run
    end

    private

    attr_reader :client

    def reconcile_orders(run)
      return { checked: 0, discrepancies: 0 } unless live_mode?

      broker_orders = fetch_broker_orders
      local_orders = active_local_orders
      checked = 0
      discrepancies = 0

      broker_orders.each do |bo|
        checked += 1
        local = local_orders[bo[:order_id].to_s]
        next unless local # broker-only orders are handled separately

        compare_order_fields(run, bo, local).each { discrepancies += 1 }
      end

      # Detect orders we think are active but broker doesn't know about
      orphaned = local_orders.keys - broker_orders.map { |o| o[:order_id].to_s }
      orphaned.each do |oid|
        record_discrepancy(run, 'order', oid, 'existence', 'active', 'not_found', 'critical')
        discrepancies += 1
      end

      run.update!(orders_checked: checked)
      { checked: checked, discrepancies: discrepancies }
    end

    def reconcile_positions(run)
      return { checked: 0, discrepancies: 0 } unless live_mode?

      broker_positions = fetch_broker_positions
      local_trackers = active_local_positions
      checked = 0
      discrepancies = 0

      broker_positions.each do |bp|
        checked += 1
        key = position_key(bp)
        local = local_trackers[key]
        next unless local

        compare_position_fields(run, bp, local).each { discrepancies += 1 }
      end

      run.update!(positions_checked: checked)
      { checked: checked, discrepancies: discrepancies }
    end

    def reconcile_funds(run)
      return { checked: 0, discrepancies: 0 } unless live_mode?

      broker_funds = fetch_broker_funds
      local_wallet = local_wallet_state
      checked = 1
      discrepancies = 0

      if broker_funds && local_wallet
        margin_diff = (broker_funds[:available_margin].to_f - local_wallet[:cash].to_f).abs
        if margin_diff > 1000 # ₹1000 tolerance
          record_discrepancy(run, 'fund', 'margin', 'available_margin',
                             local_wallet[:cash].to_s, broker_funds[:available_margin].to_s,
                             margin_diff > 10_000 ? 'critical' : 'warning')
          discrepancies += 1
        end
      end

      run.update!(funds_checked: checked)
      { checked: checked, discrepancies: discrepancies }
    end

    def compare_order_fields(run, broker, local)
      discrepancies = []
      # Compare status
      if broker[:status].to_s.downcase != local[:status].to_s.downcase
        record_discrepancy(run, 'order', broker[:order_id].to_s, 'status',
                           local[:status], broker[:status], 'critical')
        discrepancies << :status
      end
      discrepancies
    end

    def compare_position_fields(run, broker, local)
      discrepancies = []
      bq = broker[:quantity].to_i
      lq = local.quantity.to_i
      if bq != lq
        record_discrepancy(run, 'position', position_key(broker), 'quantity',
                           lq.to_s, bq.to_s, 'critical')
        discrepancies << :quantity
      end
      discrepancies
    end

    def record_discrepancy(run, entity_type, entity_id, field, local_val, broker_val, severity)
      run.discrepancies.create!(
        entity_type: entity_type,
        entity_id: entity_id,
        field_name: field,
        local_value: local_val,
        broker_value: broker_val,
        severity: severity,
        resolution: 'pending'
      )
    end

    def finalize_run(run, results)
      total_discrepancies = results.values.sum { |r| r[:discrepancies] }
      status = total_discrepancies.zero? ? 'passed' : 'failed'

      run.update!(
        status: status,
        discrepancies_found: total_discrepancies,
        completed_at: Time.current,
        summary: results
      )

      halt_on_critical!(run) if run.discrepancies.critical.any?
      run
    end

    def halt_on_critical!(run)
      reason = "Broker reconciliation found #{run.discrepancies.critical.count} critical discrepancies"
      Rails.logger.error("[BrokerRecon] HALTING: #{reason}")
      Risk::CircuitBreaker.instance.trip!(reason: reason)
      run.update!(halted_trading: true)
    end

    def fetch_broker_orders
      response = client.orders
      return [] unless response.is_a?(Hash) && response[:data].is_a?(Array)

      response[:data]
    rescue StandardError => e
      Rails.logger.error("[BrokerRecon] fetch_broker_orders failed: #{e.message}")
      []
    end

    def fetch_broker_positions
      response = client.positions
      return [] unless response.is_a?(Hash) && response[:data].is_a?(Array)

      response[:data]
    rescue StandardError => e
      Rails.logger.error("[BrokerRecon] fetch_broker_positions failed: #{e.message}")
      []
    end

    def fetch_broker_funds
      response = client.fund_limit
      return nil unless response.is_a?(Hash)

      response[:data]
    rescue StandardError => e
      Rails.logger.error("[BrokerRecon] fetch_broker_funds failed: #{e.message}")
      nil
    end

    def active_local_orders
      # Returns hash of order_no => tracker for active orders
      PositionTracker.where(paper: false).active
                     .index_by(&:order_no)
    end

    def active_local_positions
      PositionTracker.where(paper: false).active
                     .index_by { |t| "#{t.segment}:#{t.security_id}" }
    end

    def local_wallet_state
      Ledger::WalletReader.snapshot(mode: :live)
    rescue StandardError => e
      Rails.logger.error("[BrokerRecon] local_wallet_state failed: #{e.message}")
      nil
    end

    def position_key(bp)
      "#{bp[:exchange_segment]}:#{bp[:security_id]}"
    end

    def build_client
      DhanHQ::Client.new
    rescue StandardError
      nil
    end

    def live_mode?
      !AlgoConfig.dig('paper_trading', 'enabled')
    end

    def current_mode
      live_mode? ? 'live' : 'paper'
    end
  end
end
