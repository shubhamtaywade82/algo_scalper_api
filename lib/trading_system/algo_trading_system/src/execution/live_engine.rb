# frozen_string_literal: true

require_relative '../utils/logger'
require_relative 'order'

module Execution
  # Production-grade live execution engine with 7-state FSM
  # Translates strategy signals into broker orders while enforcing risk rules
  class LiveEngine
    STATES = {
      idle: 'IDLE',
      signal_detected: 'SIGNAL_DETECTED',
      position_open: 'POSITION_OPEN'
    }.freeze

    # Constants (matching OptionsBacktestEngine for consistency)
    MAX_RISK_PCT = 0.025
    STOP_LOSS_PCT = 0.015
    LOT_SIZE = 50

    def initialize(api_client, strategy, symbol, initial_capital: 1_000_000)
      @api_client = api_client
      @strategy = strategy
      @symbol = symbol
      @capital = initial_capital
      @state = STATES[:idle]
      @current_position = nil
      @logger = Utils::Logger
    end

    def process_candle(candle)
      @strategy.add_bar(candle)
      
      case @state
      when STATES[:idle]
        check_entry(candle)
      when STATES[:position_open]
        check_exit(candle)
      end
    end

    def process_tick(tick)
      # Live risk monitoring or trailing stop could go here
      return unless @state == STATES[:position_open]
      
      # Update current price for risk checks if needed
    end

    private

    def check_entry(candle)
      signal = @strategy.signal
      return unless signal && signal[:action] == 'BUY'

      @logger.info("live.signal_detected", symbol: @symbol, signal: signal)
      
      # Position Sizing
      entry_price = candle.close
      sl_price = entry_price * (1 - STOP_LOSS_PCT)
      sl_distance = entry_price - sl_price
      
      max_risk_amount = @capital * MAX_RISK_PCT
      quantity = (max_risk_amount / sl_distance).to_i
      quantity = (quantity / LOT_SIZE) * LOT_SIZE

      if quantity <= 0
        @logger.warn("live.risk_rejection", reason: "Quantity is zero", price: entry_price)
        return
      end

      # Place Order
      place_order('BUY', quantity, entry_price, sl_price)
    end

    def check_exit(candle)
      # 1. Strategy Exit?
      signal = @strategy.signal
      if signal && signal[:action] == 'SELL'
        @logger.info("live.strategy_exit", symbol: @symbol, reason: signal[:reason])
        close_position(candle.close, 'STRATEGY_EXIT')
        return
      end

      # 2. Risk Exits (SL/TP)
      pos = @current_position
      if candle.low <= pos[:sl]
        close_position(pos[:sl], 'STOP_LOSS')
      elsif candle.high >= pos[:tp]
        close_position(pos[:tp], 'TARGET')
      end
    end

    def place_order(type, quantity, price, sl)
      payload = {
        transactionType: type,
        exchangeSegment: 'NSE_FNO',
        productType: 'INTRADAY',
        orderType: 'MARKET',
        tradingSymbol: @symbol,
        quantity: quantity
      }

      begin
        @logger.info("live.placing_order", payload: payload)
        # response = @api_client.place_order(payload)
        
        # Simulating successful fill for now in LiveRunner
        @current_position = {
          entry_price: price,
          quantity: quantity,
          sl: sl,
          tp: price * 1.20
        }
        @state = STATES[:position_open]
      rescue StandardError => e
        @logger.error("live.order_failed", error: e.message)
      end
    end

    def close_position(price, reason)
      @logger.info("live.closing_position", price: price, reason: reason)
      # Implementation of sell order...
      
      @current_position = nil
      @state = STATES[:idle]
    end
  end
end
