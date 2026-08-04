# frozen_string_literal: true

module Ai
  module TradingAgent
    # Efficient tool registry wrapping existing Instrument + SMC + Options infrastructure.
    # Each tool uses Instrument records directly — no redundant MCP calls.
    class ToolRegistry
      INDEX_SYMBOLS = %w[NIFTY NIFTY50 BANKNIFTY SENSEX NIFTYBANK NIFTY100 NIFTY200].freeze

      SYMBOL_MAP = {
        'NIFTY' => 'Nifty 50',
        'NIFTY50' => 'Nifty 50',
        'NIFTY 50' => 'Nifty 50',
        'NIFTYBANK' => 'Nifty Bank',
        'BANKNIFTY' => 'Nifty Bank',
        'SENSEX' => 'Sensex',
        'NIFTY100' => 'Nifty 100',
        'NIFTY200' => 'Nifty 200'
      }.freeze

      CUSTOM_TOOLS = {
        'get_instrument' => {
          description: 'Find instrument by symbol. Returns security_id, exchange, segment, lot_size (underlying), instrument_type. ' \
                       'For options lot_size, use get_option_intelligence instead.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Trading symbol (e.g. "NIFTY", "SENSEX", "RELIANCE", "TCS")' }
            },
            required: %w[symbol]
          }
        },
        'get_market_snapshot' => {
          description: 'Get LTP + technical indicators (RSI, MACD, ADX, Supertrend, ATR, Bollinger) in one call. ' \
                       'Use after get_instrument. Returns everything needed for analysis.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Symbol from get_instrument' },
              interval: { type: 'string', description: 'Candle interval: "5", "15", "60" (default "15")' }
            },
            required: %w[symbol]
          }
        },
        'get_option_intelligence' => {
          description: 'Get option chain with ATM strike, expiries, near-ATM strikes with LTP/OI/IV. ' \
                       'For indices only (NIFTY, BANKNIFTY, SENSEX). Returns condensed chain data.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Index symbol (e.g. "NIFTY", "BANKNIFTY", "SENSEX")' },
              expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD (optional, uses nearest)' }
            },
            required: %w[symbol]
          }
        },
        'get_smc_analysis' => {
          description: 'Full Smart Money Concepts analysis: trend, BOS/CHoCH, order blocks, liquidity, FVG, PD zones. ' \
                       'Uses MTF confluence (60m + 15m + 5m). One call gives complete SMC picture.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Symbol from get_instrument' }
            },
            required: %w[symbol]
          }
        },
        'get_historical_data' => {
          description: 'Get historical OHLC candles (daily or intraday). Returns array of {date, open, high, low, close, volume}.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Symbol from get_instrument' },
              interval: { type: 'string', description: '"daily" for EOD, "5"/"15"/"60" for intraday' },
              days: { type: 'integer', description: 'Number of trading days (default 20)' }
            },
            required: %w[symbol]
          }
        },
        'validate_trade_risk' => {
          description: 'Deterministic pre-trade risk gate. Validates stop direction, R:R ratio (>= 1.5), risk percent (<= 2%).',
          parameters: {
            type: 'object',
            properties: {
              action: { type: 'string', enum: %w[BUY SELL], description: 'Trade direction' },
              entry_price: { type: 'number', description: 'Entry price' },
              stop_loss: { type: 'number', description: 'Stop loss price' },
              take_profit: { type: 'number', description: 'Take profit price' },
              risk_percent: { type: 'number', description: 'Risk as % of capital' },
              equity: { type: 'number', description: 'Current account equity' }
            },
            required: %w[action entry_price stop_loss take_profit risk_percent equity]
          }
        },
        'position_sizing' => {
          description: 'Calculate position size. ALWAYS pass symbol (e.g. "NIFTY") so lot_size is auto-detected from derivatives. Without symbol, quantity will NOT be lot-aligned.',
          parameters: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'REQUIRED for options: "NIFTY", "BANKNIFTY", or "SENSEX". Auto-detects lot_size from nearest derivative expiry.' },
              equity: { type: 'number', description: 'Current account equity' },
              risk_percent: { type: 'number', description: 'Max risk per trade as % of equity' },
              entry_price: { type: 'number', description: 'Planned entry price (option premium)' },
              stop_loss: { type: 'number', description: 'Stop loss price (option premium)' },
              lot_size: { type: 'integer', description: 'Lot size override. If omitted and symbol is provided, auto-detected from derivatives.' }
            },
            required: %w[equity risk_percent entry_price stop_loss]
          }
        },
        'get_trading_stats' => {
          description: 'Get current trading statistics for today (win rate, PnL, positions count).',
          parameters: {
            type: 'object',
            properties: {},
            required: []
          }
        }
      }.freeze

      class << self
        def tools_for_ollama
          CUSTOM_TOOLS.map { |name, spec| build_tool_schema(name, spec) }
        end

        def execute(tool_name, arguments = {})
          handler = custom_handlers[tool_name]
          return { error: 'unknown_tool', tool_name: tool_name } unless handler

          result = handler.call(arguments)
          clean_result(result)
        rescue StandardError => e
          { error: 'tool_call_failed', tool_name: tool_name, message: e.message }
        end

        private

        def build_tool_schema(name, spec)
          {
            type: 'function',
            function: {
              name: name,
              description: spec[:description],
              parameters: spec[:parameters]
            }
          }
        end

        def clean_result(result)
          return result unless result.is_a?(Hash)

          result.transform_values do |v|
            case v
            when Time, DateTime, Date then v.iso8601
            when Symbol then v.to_s
            when BigDecimal then v.to_f
            when Hash then clean_result(v)
            when Array then v.map { |i| i.is_a?(Hash) ? clean_result(i) : i }
            else v
            end
          end
        rescue StandardError
          { raw: result.to_s }
        end

        def custom_handlers
          {
            'get_instrument' => method(:handle_get_instrument),
            'get_market_snapshot' => method(:handle_get_market_snapshot),
            'get_option_intelligence' => method(:handle_get_option_intelligence),
            'get_smc_analysis' => method(:handle_get_smc_analysis),
            'get_historical_data' => method(:handle_get_historical_data),
            'validate_trade_risk' => method(:handle_validate_trade_risk),
            'position_sizing' => method(:handle_position_sizing),
            'get_trading_stats' => method(:handle_get_trading_stats)
          }
        end

        # --- Instrument Lookup ---

        def find_instrument(symbol)
          sym = symbol.to_s.strip.upcase
          is_index = INDEX_SYMBOLS.any? { |i| sym.include?(i) }

          if is_index
            # Use SYMBOL_MAP for exact match
            display_name = SYMBOL_MAP[sym]
            if display_name
              Instrument.where(segment: 'index')
                        .where('display_name ILIKE ?', display_name)
                        .first
            else
              # Fallback: exact match only (avoid LIKE matching unrelated instruments)
              Instrument.where(segment: 'index')
                        .where('display_name ILIKE ?', sym)
                        .first
            end
          else
            # Stocks: search by display_name (case-insensitive) + segment=equity
            Instrument.where(segment: 'equity')
                      .where('display_name ILIKE ?', "%#{sym}%")
                      .order(updated_at: :desc)
                      .first
          end
        end

        def handle_get_instrument(args)
          symbol = args['symbol']
          return { error: 'Missing symbol' } if symbol.blank?

          instrument = find_instrument(symbol)
          return { error: "Instrument not found: #{symbol}" } unless instrument

          {
            id: instrument.id,
            security_id: instrument.security_id,
            display_name: instrument.display_name,
            exchange: instrument.exchange,
            segment: instrument.segment,
            instrument_type: instrument.instrument_type,
            lot_size: instrument.lot_size,
            option_lot_size: instrument.lot_size_from_derivatives,
            expiry_flag: instrument.expiry_flag,
            underlying_symbol: instrument.underlying_symbol
          }
        end

        # --- Market Data ---

        def handle_get_market_snapshot(args)
          symbol = args['symbol']
          interval = args['interval'] || '15'
          return { error: 'Missing symbol' } if symbol.blank?

          instrument = find_instrument(symbol)
          return { error: "Instrument not found: #{symbol}" } unless instrument

          result = { symbol: instrument.display_name, security_id: instrument.security_id, interval: interval }

          # LTP
          ltp = instrument.ltp
          result[:ltp] = ltp.to_f if ltp

          # Candles + indicators
          series = instrument.candles(interval: interval)
          if series&.candles&.any?
            result[:candles_count] = series.candles.length
            result[:indicators] = {
              rsi: series.rsi(14),
              macd: series.macd(12, 26, 9),
              adx: series.adx(14),
              supertrend: series.supertrend_signal,
              atr: series.atr(14),
              bollinger: series.bollinger_bands(period: 20)
            }
          else
            result[:indicators] = { error: 'No candle data available' }
          end

          result
        end

        # --- Option Intelligence ---

        def handle_get_option_intelligence(args)
          symbol = args['symbol']
          expiry = args['expiry']
          return { error: 'Missing symbol' } if symbol.blank?

          instrument = find_instrument(symbol)
          return { error: "Instrument not found: #{symbol}" } unless instrument
          return { error: "#{instrument.display_name} is not an index — options only available for indices" } unless instrument.segment == 'index'

          result = { symbol: instrument.display_name, security_id: instrument.security_id, fetched_at: Time.current.iso8601 }

          # Option lot_size from nearest derivative (not underlying)
          result[:lot_size] = instrument.lot_size_from_derivatives

          # Expiries
          expiries = instrument.expiry_list
          result[:expiries] = expiries.first(5)
          selected = expiry || expiries.first
          result[:selected_expiry] = selected

          return { error: 'No expiries available' } unless selected

          # Days to expiry
          begin
            expiry_date = Date.parse(selected)
            today = Time.zone.today
            result[:days_to_expiry] = (expiry_date - today).to_i
            result[:is_expiry_today] = result[:days_to_expiry].zero?
            result[:is_expiry_week] = result[:days_to_expiry].between?(0, 7)
          rescue StandardError
            # ignore
          end

          # Option chain
          chain = instrument.option_chain(expiry: selected)
          if chain
            last_price = chain[:last_price] || chain['last_price']
            oc = chain[:oc] || chain['oc'] || {}
            result[:underlying_ltp] = last_price.to_f if last_price

            if oc.is_a?(Hash) && oc.any?
              # ATM strike: round LTP to nearest 50 for indices
              atm = last_price ? (last_price.to_f / 50).round * 50 : nil
              result[:atm_strike] = atm

              # Get strikes near ATM (±200 points, ~4 strikes each side)
              near = oc.select do |k|
                strike_val = k.to_f
                atm && (strike_val - atm).abs <= 200
              end

              result[:strikes] = near.map do |strike_key, data|
                ce = data['ce'] || data[:ce]
                pe = data['pe'] || data[:pe]

                strike_info = { strike: strike_key.to_f }

                if ce
                  greeks = ce['greeks'] || ce[:greeks] || {}
                  strike_info[:call] = {
                    ltp: ce['last_price'] || ce[:last_price],
                    oi: ce['oi'] || ce[:oi],
                    iv: ce['implied_volatility'] || ce[:implied_volatility] || greeks['iv'] || greeks[:iv],
                    delta: greeks['delta'] || greeks[:delta],
                    theta: greeks['theta'] || greeks[:theta],
                    gamma: greeks['gamma'] || greeks[:gamma],
                    vega: greeks['vega'] || greeks[:vega],
                    bid: ce['top_bid_price'] || ce[:top_bid_price],
                    ask: ce['top_ask_price'] || ce[:top_ask_price],
                    volume: ce['volume'] || ce[:volume]
                  }
                end

                if pe
                  greeks = pe['greeks'] || pe[:greeks] || {}
                  strike_info[:put] = {
                    ltp: pe['last_price'] || pe[:last_price],
                    oi: pe['oi'] || pe[:oi],
                    iv: pe['implied_volatility'] || pe[:implied_volatility] || greeks['iv'] || greeks[:iv],
                    delta: greeks['delta'] || greeks[:delta],
                    theta: greeks['theta'] || greeks[:theta],
                    gamma: greeks['gamma'] || greeks[:gamma],
                    vega: greeks['vega'] || greeks[:vega],
                    bid: pe['top_bid_price'] || pe[:top_bid_price],
                    ask: pe['top_ask_price'] || pe[:top_ask_price],
                    volume: pe['volume'] || pe[:volume]
                  }
                end

                strike_info
              end

              # ATM strike details (convenience)
              atm_data = oc[atm.to_s] || oc["#{atm}.0"]
              if atm_data
                ce = atm_data['ce'] || atm_data[:ce]
                pe = atm_data['pe'] || atm_data[:pe]
                result[:atm_call] = summarize_leg(ce)
                result[:atm_put] = summarize_leg(pe)
              end
            end
          else
            result[:error] = 'Could not fetch option chain'
          end

          result
        rescue StandardError => e
          { error: e.message }
        end

        def summarize_leg(leg)
          return nil unless leg.is_a?(Hash)

          greeks = leg['greeks'] || leg[:greeks] || {}
          {
            ltp: leg['last_price'] || leg[:last_price],
            oi: leg['oi'] || leg[:oi],
            iv: leg['implied_volatility'] || leg[:implied_volatility] || greeks['iv'] || greeks[:iv],
            delta: greeks['delta'] || greeks[:delta],
            theta: greeks['theta'] || greeks[:theta],
            gamma: greeks['gamma'] || greeks[:gamma],
            vega: greeks['vega'] || greeks[:vega],
            bid: leg['top_bid_price'] || leg[:top_bid_price],
            ask: leg['top_ask_price'] || leg[:top_ask_price],
            volume: leg['volume'] || leg[:volume]
          }
        end

        # --- SMC Analysis ---

        def handle_get_smc_analysis(args)
          symbol = args['symbol']
          return { error: 'Missing symbol' } if symbol.blank?

          instrument = find_instrument(symbol)
          return { error: "Instrument not found: #{symbol}" } unless instrument

          result = { symbol: instrument.display_name }
          timeframes = { '60' => 'HTF', '15' => 'MTF', '5' => 'LTF' }
          contexts = {}

          timeframes.each do |tf, label|
            series = instrument.candles(interval: tf)
            next unless series&.candles&.any?

            ctx = Smc::Context.new(series)
            contexts[label] = {
              trend: ctx.trend,
              phase: ctx.phase,
              pd: ctx.pd&.to_h,
              liquidity: ctx.liquidity&.to_h,
              order_blocks: ctx.order_blocks&.map(&:to_h)&.first(3),
              fvg: ctx.fvg&.to_h,
              swing: ctx.swing_structure&.to_h,
              internal: ctx.internal_structure&.to_h
            }
          end

          # Confluence
          trends = contexts.values.filter_map { |c| c[:trend] }.compact
          result[:htf] = contexts['HTF']
          result[:mtf] = contexts['MTF']
          result[:ltf] = contexts['LTF']
          result[:confluence] = trends.uniq.size == 1 ? 'aligned' : 'diverged'
          result[:bias] = trends.first&.to_s || 'neutral'

          result
        end

        # --- Historical Data ---

        def handle_get_historical_data(args)
          symbol = args['symbol']
          interval = args['interval'] || '15'
          days = args['days'] || 20
          return { error: 'Missing symbol' } if symbol.blank?

          instrument = find_instrument(symbol)
          return { error: "Instrument not found: #{symbol}" } unless instrument

          result = { symbol: instrument.display_name, interval: interval, count: 0 }

          if interval == 'daily'
            data = begin
                     instrument.historical_ohlc
            rescue StandardError
                     []
            end
            result[:candles] = data.last(days).map do |c|
              { date: c[:date] || c['date'], o: c[:open] || c['open'], h: c[:high] || c['high'],
                l: c[:low] || c['low'], c: c[:close] || c['close'], v: c[:volume] || c['volume'] }
            end
          else
            series = instrument.candles(interval: interval)
            if series&.candles&.any?
              result[:candles] = series.candles.last(days * 6).map do |c|
                { t: c.timestamp, o: c.open, h: c.high, l: c.low, c: c.close, v: c.volume }
              end
            else
              result[:candles] = []
            end
          end

          result[:count] = result[:candles]&.length || 0
          result
        end

        # --- Risk & Sizing ---

        def handle_validate_trade_risk(args)
          action = args['action']&.upcase
          entry = args['entry_price']&.to_f
          sl = args['stop_loss']&.to_f
          tp = args['take_profit']&.to_f
          risk_pct = args['risk_percent']&.to_f
          args['equity']&.to_f

          checks = {}
          checks[:stop_direction] = action == 'BUY' ? sl < entry : sl > entry if action && entry && sl

          risk = entry && sl ? (entry - sl).abs : 0
          reward = entry && tp ? (tp - entry).abs : 0
          rr = risk.positive? ? reward / risk : 0
          checks[:rr_ratio] = rr.round(2)
          checks[:rr_approved] = rr >= 1.5
          checks[:risk_percent] = risk_pct&.round(2)
          checks[:risk_approved] = risk_pct && risk_pct <= 2.0

          approved = checks[:stop_direction] && checks[:rr_approved] && checks[:risk_approved]

          { approved: approved == true, action: action, risk_checks: checks,
            message: approved ? 'APPROVED' : "REJECTED: #{checks.select { |_, v| v == false }.keys.join(', ')}" }
        end

        def handle_position_sizing(args)
          equity = args['equity']&.to_f
          risk_pct = args['risk_percent']&.to_f
          entry = args['entry_price']&.to_f
          sl = args['stop_loss']&.to_f
          return { error: 'Missing parameters' } unless equity && risk_pct && entry && sl

          lot_size = args['lot_size']&.to_i

          # Auto-detect lot_size from derivatives if not provided
          unless lot_size&.positive?
            symbol = args['symbol']
            if symbol.present?
              instrument = find_instrument(symbol)
              lot_size = instrument&.lot_size_from_derivatives
            end
          end

          risk_amount = equity * (risk_pct / 100.0)
          risk_per_unit = (entry - sl).abs
          return { error: 'SL too close to entry' } if risk_per_unit.zero?

          raw_qty = (risk_amount / risk_per_unit).floor
          if lot_size&.positive?
            qty = (raw_qty / lot_size) * lot_size
            qty = lot_size if qty.zero?
          else
            qty = raw_qty
          end
          { quantity: qty, lot_size: lot_size, risk_amount: (qty * risk_per_unit).round(2),
            risk_percent: ((qty * risk_per_unit / equity) * 100).round(2) }
        end

        def handle_get_trading_stats(_args)
          date = Time.zone.today
          stats = PositionTracker.paper_trading_stats_with_pct(date: date)
          { date: date.to_s, total_trades: stats[:total_trades], winners: stats[:winners],
            losers: stats[:losers], win_rate: stats[:win_rate],
            realized_pnl: stats[:realized_pnl_rupees], realized_pnl_pct: stats[:realized_pnl_pct] }
        end
      end
    end
  end
end
