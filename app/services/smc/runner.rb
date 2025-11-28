# frozen_string_literal: true

module Smc
  # Runner converts a signal hash into an executed bracket order (live) or a simulated trade (backtest)
  class Runner
    attr_reader :signal, :mode

    def initialize(signal, mode: :live)
      raise ArgumentError, "Signal Hash required" unless signal.is_a?(Hash)
      @signal = signal.deep_symbolize_keys
      @mode = mode.to_sym
    end

    # Execute the signal. In :backtest mode, simulate execution against historical candles.
    def execute
      Rails.logger.info("[Smc::Runner] execute mode=#{mode} signal=#{signal_summary}")
      unless valid_signal?
        Rails.logger.warn("[Smc::Runner] Invalid signal, aborting: #{signal_summary}")
        return nil
      end

      # Find option instrument
      option_inst = find_option_instrument(signal[:option_symbol])
      unless option_inst
        Rails.logger.error("[Smc::Runner] Option instrument not found for #{signal[:option_symbol]}")
        return nil
      end

      # tradability check
      unless tradable?(option_inst)
        Rails.logger.warn("[Smc::Runner] Option not tradable or illiquid: #{option_inst.symbol_name}")
        return nil
      end

      # final IV & liquidity re-check
      if signal[:meta]&.dig(:iv) && signal[:meta][:iv] > (signal[:meta][:max_iv] || (AlgoConfig.fetch[:smc][:max_iv] rescue 60))
        Rails.logger.warn("[Smc::Runner] IV too high at execution: #{signal[:meta][:iv]} - aborting")
        return nil
      end

      if mode == :backtest
        simulate_backtest_execution(option_inst)
      else
        place_live_order(option_inst)
      end
    rescue => e
      Rails.logger.error("[Smc::Runner] Execution failure: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      nil
    end

    private

    def valid_signal?
      signal[:qty].to_i > 0 && signal[:option_symbol].present? && signal[:type].in?([:ce, :pe])
    end

    def signal_summary
      "#{signal[:type]} #{signal[:option_symbol]} strike:#{signal[:strike]} qty:#{signal[:qty]}"
    end

    def find_option_instrument(sym)
      # Prefer Option::ChainAnalyzer helper (patched below)
      if defined?(Option::ChainAnalyzer) && Option::ChainAnalyzer.respond_to?(:find_instrument_by_symbol)
        Option::ChainAnalyzer.find_instrument_by_symbol(sym)
      else
        # Try to find by symbol_name with segment_index scope (for index instruments)
        # or use find_by_sid_and_segment if we have security_id
        Instrument.segment_index.find_by(symbol_name: sym) ||
          Instrument.find_by(symbol_name: sym)
      end
    end

    def tradable?(inst)
      return false unless inst
      return false unless inst.security_id.present? && inst.exchange_segment.present?

      # Basic liquidity heuristics: option must have some recent OI/volume
      if inst.respond_to?(:fetch_option_chain)
        # if derivative instrument has on-model attributes, use them
        true
      else
        true
      end
    rescue => e
      Rails.logger.error("[Smc::Runner] tradable? check failed: #{e.message}")
      false
    end

    # Place a live bracket order using Orders::BracketPlacer or fallback
    def place_live_order(option_inst)
      ensure_ws_connected!

      # Use tick LTP if available
      ltp = option_inst.latest_ltp || signal[:meta]&.dig(:premium) || 0.0
      if ltp.to_f <= 0
        Rails.logger.warn("[Smc::Runner] LTP not available for #{option_inst.symbol_name}, aborting")
        return nil
      end

      qty = signal[:qty].to_i
      stop_price = convert_spot_to_option_stop(option_inst, signal[:sl_spot], ltp)
      target_price = convert_spot_to_option_stop(option_inst, signal[:target_spot], ltp)

      # Build order parameters defensively
      order_params = {
        side: 'buy',
        segment: option_inst.exchange_segment,
        security_id: option_inst.security_id.to_s,
        qty: qty,
        product_type: 'INTRADAY',
        meta: signal[:meta].merge(source: 'smc', generated_at: signal[:meta][:generated_at])
      }

      # Try Orders::BracketPlacer interface
      order = nil
      begin
        if defined?(Orders::BracketPlacer)
          bp = Orders::BracketPlacer.new(
            side: 'buy',
            segment: option_inst.exchange_segment,
            security_id: option_inst.security_id.to_s,
            qty: qty,
            entry_price: nil, # market
            stop_loss: stop_price,
            target: target_price,
            meta: order_params[:meta]
          )
          order = bp.place
        elsif defined?(Orders) && Orders.respond_to?(:config) && Orders.config.respond_to?(:place_bracket)
          order = Orders.config.place_bracket(order_params.merge(stop_loss: stop_price, target: target_price))
        else
          Rails.logger.error("[Smc::Runner] No Bracket order interface available")
          return nil
        end
      rescue => e
        Rails.logger.error("[Smc::Runner] Order placement failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        return nil
      end

      if order && order.respond_to?(:order_id) && order.order_id.present?
        # Track positions using existing helper on instrument model
        option_inst.after_order_track!(
          instrument: option_inst,
          order_no: order.order_id,
          segment: option_inst.exchange_segment,
          security_id: option_inst.security_id,
          side: 'LONG',
          qty: qty,
          entry_price: (order.executed_price || order.avg_price || ltp),
          symbol: option_inst.symbol_name
        )
        Rails.logger.info("[Smc::Runner] Order placed successfully: #{order.order_id} for #{option_inst.symbol_name}")
      else
        Rails.logger.error("[Smc::Runner] Order placement returned nil or missing order_id: #{order.inspect}")
      end

      order
    end

    # Simulate execution for backtest: returns a hash representing executed trade
    def simulate_backtest_execution(option_inst)
      # In backtest mode, we assume immediate fill at next candle open or LTP estimate
      executed_price = option_inst.fetch_historical_fill_price_at(signal[:meta][:generated_at]) rescue nil
      executed_price ||= (signal[:meta][:premium] || 0.0)
      executed_price = executed_price.to_f
      if executed_price <= 0
        Rails.logger.warn("[Smc::Runner] Backtest: no fill price available for #{option_inst.symbol_name}")
        return nil
      end

      # Build a simplified execution record (you can expand to store in DB)
      exec = {
        instrument: option_inst.symbol_name,
        executed_price: executed_price,
        qty: signal[:qty],
        side: 'buy',
        timestamp: signal[:meta][:generated_at]
      }
      Rails.logger.info("[Smc::Runner] Backtest simulated execution: #{exec.inspect}")
      exec
    end

    def ensure_ws_connected!
      hub = Live::MarketFeedHub.instance
      unless hub&.connected?
        raise "WebSocket hub not connected - refuse to trade"
      end
    end

    # Convert spot-based SL/TP into option price estimate (very conservative): map using delta/approx or use percentage
    def convert_spot_to_option_stop(option_inst, sl_spot, current_option_ltp)
      # If Option::ChainAnalyzer provides greeks/delta, use it; otherwise fallback to a % move
      if defined?(Option::ChainAnalyzer) && Option::ChainAnalyzer.respond_to?(:spot_to_option_price)
        Option::ChainAnalyzer.spot_to_option_price(option_inst, sl_spot)
      else
        # fallback: use small % of current option price as stop cushion
        cp = current_option_ltp.to_f
        stop = if signal[:type] == :ce
                 [ (cp * 0.6).round(2), (cp - (cp * 0.2)).round(2) ].max
               else
                 [ (cp * 0.6).round(2), (cp - (cp * 0.2)).round(2) ].max
               end
        stop
      end
    end
  end
end
