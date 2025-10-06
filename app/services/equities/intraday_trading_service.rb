# frozen_string_literal: true

module Equities
  # Orchestrates the intraday equity trading workflow without affecting the options scalper.
  class IntradayTradingService
    STRATEGY = "equity_intraday"
    MAX_CONCURRENT_POSITIONS = 2
    MARKET_TIMEZONE = "Asia/Kolkata"
    MARKET_OPEN_TIME = "09:15"
    MARKET_CLOSE_TIME = "15:20"
    SQUARE_OFF_TIME = "15:15"
    RATE_LIMIT_DELAY = 1.0

    def initialize(
      client: Dhanhq.client,
      data_fetcher: Trading::DataFetcherService.new(client: client),
      signal_service: SignalService.new(data_fetcher: data_fetcher),
      position_sizer: PositionSizer.new(client: client)
    )
      @client = client
      @data_fetcher = data_fetcher
      @signal_service = signal_service
      @position_sizer = position_sizer
    end

    def execute!
      return unless @client.enabled?
      return unless trading_session?

      square_off_positions_if_needed
      return if open_positions_count >= MAX_CONCURRENT_POSITIONS

      eligible_items.find_each do |watchlist_item|
        break if open_positions_count >= MAX_CONCURRENT_POSITIONS

        instrument = instrument_for(watchlist_item)
        next unless instrument
        next if trade_already_open?(instrument.security_id)

        process_instrument(instrument)
        sleep RATE_LIMIT_DELAY if RATE_LIMIT_DELAY.positive?
      end
    end

    private

    def process_instrument(instrument)
      signal = @signal_service.signal_for(instrument)
      return unless signal&.tradable?

      plan = @position_sizer.build_plan(instrument: instrument, signal: signal)
      return unless plan.viable?

      trade_log = TradeLog.create!(
        strategy: STRATEGY,
        symbol: instrument.symbol_name,
        segment: instrument.exchange_segment,
        security_id: instrument.security_id,
        direction: signal.direction,
        quantity: plan.quantity,
        stop_price: plan.stop_price,
        target_price: plan.target_price,
        risk_amount: plan.risk_amount,
        estimated_profit: plan.estimated_profit,
        metadata: {
          adx: signal.strength.to_f,
          volume_ratio: signal.volume_ratio.to_f,
          obv_direction: signal.obv_direction
        }
      )

      order = submit_order(instrument, signal, plan)
      trade_log.mark_open!(order_id: extract_order_id(order), entry_price: signal.ltp)
    rescue StandardError => e
      Rails.logger.error("Equity trade failed for #{instrument.symbol_name}: #{e.class} - #{e.message}")
      trade_log&.mark_failed!(e.message)
    end

    def submit_order(instrument, signal, plan)
      stop_diff = (signal.ltp - plan.stop_price).abs.to_f
      target_diff = (plan.target_price - signal.ltp).abs.to_f

      @client.create_super_order(
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        transaction_type: signal.direction == :long ? "BUY" : "SELL",
        order_type: "MARKET",
        quantity: plan.quantity,
        product_type: "INTRADAY",
        bo_stop_loss_value: stop_diff,
        bo_profit_value: target_diff,
        remarks: "Equity intraday auto-entry for #{instrument.symbol_name}"
      )
    end

    def square_off_positions_if_needed
      return unless nearing_square_off?

      TradeLog.for_strategy(STRATEGY).status_open.find_each do |log|
        close_trade(log)
      end
    end

    def close_trade(log)
      instrument = Instrument.find_by(security_id: log.security_id)
      return unless instrument

      exit_order = @client.place_order(
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        transaction_type: log.direction_long? ? "SELL" : "BUY",
        order_type: "MARKET",
        quantity: log.quantity,
        product_type: "INTRADAY",
        remarks: "Auto square-off for #{instrument.symbol_name}"
      )

      exit_price = instrument.latest_ltp
      log.close!(exit_order_id: extract_order_id(exit_order), exit_price: exit_price)
    rescue StandardError => e
      Rails.logger.error("Failed to square off #{log.security_id}: #{e.class} - #{e.message}")
    end

    def extract_order_id(order)
      return order.order_id if order.respond_to?(:order_id)
      return order[:order_id] if order.respond_to?(:[]) && order[:order_id]
      return order["order_id"] if order.respond_to?(:[]) && order["order_id"]

      nil
    end

    def instrument_for(watchlist_item)
      watchlist_item.instrument || Instrument.find_by(security_id: watchlist_item.security_id)
    end

    def eligible_items
      WatchlistItem.active.where(kind: :equity)
    end

    def trade_already_open?(security_id)
      active_trades.where(security_id: security_id).exists?
    end

    def open_positions_count
      active_trades.count
    end

    def active_trades
      TradeLog.for_strategy(STRATEGY).where(status: %i[pending open])
    end

    def trading_session?
      now = current_time
      market_open = parse_time(now, MARKET_OPEN_TIME)
      market_close = parse_time(now, MARKET_CLOSE_TIME)
      now.between?(market_open, market_close)
    end

    def nearing_square_off?
      now = current_time
      now >= parse_time(now, SQUARE_OFF_TIME)
    end

    def current_time
      Time.current.in_time_zone(MARKET_TIMEZONE)
    end

    def parse_time(reference, clock_time)
      hour, minute = clock_time.split(":").map(&:to_i)
      reference.change(hour: hour, min: minute, sec: 0)
    end
  end
end
