# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Defines and builds the tool registry
      module ToolRegistry
        def build_tools_registry
          # NEW: Coarse-grained tools for orchestration layer
          orchestration_tools = {
            'resolve_instrument' => {
              description: 'Resolve instrument from symbol (Rails-controlled, not LLM choice). Returns instrument_id for use in other tools.',
              parameters: [
                { name: 'symbol', type: 'string', description: 'Instrument symbol (e.g., "NIFTY", "RELIANCE", "TCS")' }
              ],
              handler: method(:tool_resolve_instrument)
            },
            'get_ltp' => {
              description: 'Get Last Traded Price for resolved instrument',
              parameters: [
                { name: 'instrument_id', type: 'integer', description: 'Instrument ID from resolve_instrument tool' }
              ],
              handler: method(:tool_get_ltp)
            },
            'fetch_candles' => {
              description: 'Fetch historical candles (automatically narrowed to last 50)',
              parameters: [
                { name: 'instrument_id', type: 'integer', description: 'Instrument ID from resolve_instrument tool' },
                { name: 'interval', type: 'string', description: 'Timeframe: 5m, 15m, 1h, daily' }
              ],
              handler: method(:tool_fetch_candles)
            },
            'compute_indicators' => {
              description: 'Compute ALL indicators for instrument (RSI, MACD, ADX, Supertrend, ATR, BollingerBands) in one call',
              parameters: [
                { name: 'instrument_id', type: 'integer', description: 'Instrument ID from resolve_instrument tool' },
                { name: 'timeframes', type: 'array', description: 'Array of timeframes: ["5m", "15m"]' }
              ],
              handler: method(:tool_compute_indicators)
            },
            'fetch_option_chain' => {
              description: 'Fetch option chain (automatically filtered to ATM ±1 ±2)',
              parameters: [
                { name: 'instrument_id', type: 'integer', description: 'Instrument ID from resolve_instrument tool' }
              ],
              handler: method(:tool_fetch_option_chain)
            },
            'check_data_availability' => {
              description: 'Check if sufficient data exists for analysis',
              parameters: [],
              handler: method(:tool_check_data_availability)
            }
          }

          # EXISTING: Legacy tools (kept for backward compatibility, but prefer orchestration tools)
          legacy_tools = {
            'get_comprehensive_analysis' => {
              description: 'Get comprehensive analysis data for an index or stock in ONE call: finds instrument, fetches LTP, historical data (up to 200 candles), and calculates ALL available indicators (RSI, MACD, ADX, Supertrend, ATR, BollingerBands). Use this instead of multiple separate tool calls for efficiency. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks (RELIANCE, TCS, etc.) use "equity".',
              parameters: [
                { name: 'underlying_symbol', type: 'string',
                  description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc. Auto-detects exchange: SENSEX→BSE, NIFTY/BANKNIFTY→NSE' },
                { name: 'exchange', type: 'string',
                  description: 'Exchange: "NSE" or "BSE". Optional - auto-detected from underlying_symbol if not provided (NIFTY/BANKNIFTY→NSE, SENSEX→BSE, others→NSE)' },
                { name: 'segment', type: 'string',
                  description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' },
                { name: 'interval', type: 'string',
                  description: 'Timeframe for historical data: 1, 5, 15, 30, 60 (minutes). Default: 5' },
                { name: 'max_candles', type: 'integer',
                  description: 'Maximum number of candles to fetch (default: 200, max: 200)' }
              ],
              handler: method(:tool_get_comprehensive_analysis)
            },
            'get_index_ltp' => {
              description: 'Get Last Traded Price (LTP) for an index (NIFTY, BANKNIFTY, SENSEX)',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' }
              ],
              handler: method(:tool_get_index_ltp)
            },
            'get_instrument_ltp' => {
              description: 'Get LTP for a specific instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
              parameters: [
                { name: 'underlying_symbol', type: 'string',
                  description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
                { name: 'exchange', type: 'string',
                  description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
                { name: 'segment', type: 'string',
                  description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' }
              ],
              handler: method(:tool_get_instrument_ltp)
            },
            'get_ohlc' => {
              description: 'Get OHLC (Open, High, Low, Close) data for an instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
              parameters: [
                { name: 'underlying_symbol', type: 'string',
                  description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
                { name: 'exchange', type: 'string',
                  description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
                { name: 'segment', type: 'string',
                  description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' }
              ],
              handler: method(:tool_get_ohlc)
            },
            'calculate_indicator' => {
              description: 'Calculate a technical indicator for an index. Available indicators: RSI (momentum), MACD (trend/momentum), ADX (trend strength), Supertrend (trend direction), ATR (volatility), BollingerBands (volatility/price extremes). Use multiple indicators for comprehensive analysis.',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
                { name: 'indicator', type: 'string',
                  description: 'Indicator name: RSI, MACD, ADX, Supertrend, ATR, BollingerBands (or BB). Use the indicator most appropriate for your analysis - don\'t limit to RSI!' },
                { name: 'period', type: 'integer',
                  description: 'Period for the indicator (optional, defaults: RSI=14, MACD=12/26/9, ADX=14, Supertrend=7, ATR=14, BollingerBands=20)' },
                { name: 'interval', type: 'string', description: 'Timeframe: 1, 5, 15, 30, 60 (minutes). Default: 1' },
                { name: 'multiplier', type: 'number',
                  description: 'Multiplier for Supertrend (optional, default: 3.0)' },
                { name: 'std_dev', type: 'number',
                  description: 'Standard deviation for BollingerBands (optional, default: 2.0)' }
              ],
              handler: method(:tool_calculate_indicator)
            },
            'get_historical_data' => {
              description: 'Get historical OHLC candle data for an index or instrument. IMPORTANT: Use correct segment - indices (NIFTY, BANKNIFTY, SENSEX) use "index", stocks/equities (RELIANCE, TCS, INFY) use "equity". For indices, use correct exchange - NIFTY and BANKNIFTY are on NSE, SENSEX is on BSE.',
              parameters: [
                { name: 'underlying_symbol', type: 'string',
                  description: 'Underlying symbol. For indices: "NIFTY", "BANKNIFTY", "SENSEX". For stocks: "RELIANCE", "TCS", "INFY", etc.' },
                { name: 'exchange', type: 'string',
                  description: 'Exchange: "NSE" or "BSE". IMPORTANT: NIFTY and BANKNIFTY use "NSE", SENSEX uses "BSE". For stocks, typically "NSE". Default: Auto-detected from underlying_symbol (NIFTY/BANKNIFTY=NSE, SENSEX=BSE, others=NSE)' },
                { name: 'segment', type: 'string',
                  description: 'Segment: "index" for indices (NIFTY, BANKNIFTY, SENSEX), "equity" for stocks (RELIANCE, TCS, etc.), "derivatives" for futures/options. Default: Auto-detected (if symbol is known index, uses "index", otherwise tries "equity")' },
                { name: 'interval', type: 'string',
                  description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
                { name: 'from_date', type: 'string',
                  description: 'Start date (YYYY-MM-DD). Default: 3 days before to_date. IMPORTANT: Must be at least 1 day before to_date' },
                { name: 'to_date', type: 'string',
                  description: 'End date (YYYY-MM-DD). Default: today. If from_date is same or later, it will be auto-adjusted to 1 day before to_date' }
              ],
              handler: method(:tool_get_historical_data)
            },
            'analyze_option_chain' => {
              description: 'Analyze option chain for an index and get best candidates',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
                { name: 'direction', type: 'string', description: 'bullish or bearish' },
                { name: 'limit', type: 'integer', description: 'Number of candidates to return (default: 5)' }
              ],
              handler: method(:tool_analyze_option_chain)
            },
            'get_trading_stats' => {
              description: 'Get current trading statistics (win rate, PnL, positions)',
              parameters: [
                { name: 'date', type: 'string', description: 'Date in YYYY-MM-DD format (optional, defaults to today)' }
              ],
              handler: method(:tool_get_trading_stats)
            },
            'get_active_positions' => {
              description: 'Get currently active trading positions',
              parameters: [],
              handler: method(:tool_get_active_positions)
            },
            'calculate_advanced_indicator' => {
              description: 'Calculate advanced indicators (HolyGrail, TrendDuration) for an index',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
                { name: 'indicator', type: 'string',
                  description: 'Advanced indicator name: HolyGrail, TrendDuration' },
                { name: 'interval', type: 'string',
                  description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
                { name: 'config', type: 'object', description: 'Optional configuration parameters (JSON object)' }
              ],
              handler: method(:tool_calculate_advanced_indicator)
            },
            'run_backtest' => {
              description: 'Run a backtest on historical data for an index',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
                { name: 'interval', type: 'string',
                  description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
                { name: 'days_back', type: 'integer', description: 'Number of days to backtest (default: 90)' },
                { name: 'supertrend_cfg', type: 'object',
                  description: 'Supertrend configuration: { period: 7, multiplier: 3.0 } (optional)' },
                { name: 'adx_min_strength', type: 'number',
                  description: 'Minimum ADX strength threshold (optional, default: 0)' }
              ],
              handler: method(:tool_run_backtest)
            },
            'optimize_indicator' => {
              description: 'Optimize indicator parameters for an index using historical data',
              parameters: [
                { name: 'index_key', type: 'string', description: 'Index key: NIFTY, BANKNIFTY, or SENSEX' },
                { name: 'interval', type: 'string',
                  description: 'Timeframe: 1, 5, 15, 25, 60 (minutes). Default: 5' },
                { name: 'lookback_days', type: 'integer',
                  description: 'Number of days to use for optimization (default: 45)' },
                { name: 'test_mode', type: 'boolean',
                  description: 'Use reduced parameter space for faster testing (default: false)' }
              ],
              handler: method(:tool_optimize_indicator)
            }
          }

          # Merge: orchestration tools first (preferred), then legacy tools
          orchestration_tools.merge(legacy_tools)
        end
      end
    end
  end
end
