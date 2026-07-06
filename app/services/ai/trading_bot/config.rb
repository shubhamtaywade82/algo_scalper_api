# frozen_string_literal: true

module Ai
  module TradingBot
    # Configuration for the automated trading bot.
    # Loads from YAML + ENV overrides.
    class Config
      DEFAULTS = {
        mode: 'paper',
        symbols: %w[NIFTY BANKNIFTY],
        poll_interval_sec: 30,
        max_risk_per_trade_pct: 2.0,
        max_open_trades: 3,
        max_setups_per_symbol: 1,
        model: nil,
        initial_balance: 100_000.0,
        slippage_pct: 0.05,
        taker_fee: 0.0004,
        maker_fee: 0.0002,
        telegram_notify: true,
        timeframes: {
          entry: '15',
          trend: '60'
        }
      }.freeze

      attr_reader :mode, :symbols, :poll_interval_sec, :max_risk_per_trade_pct,
                  :max_open_trades, :max_setups_per_symbol, :model,
                  :initial_balance, :slippage_pct, :taker_fee, :maker_fee,
                  :telegram_notify, :timeframes, :verbose

      def initialize(attrs = {})
        merged = DEFAULTS.merge(attrs.transform_keys(&:to_sym))
        @mode = merged[:mode].to_s.downcase
        @symbols = Array(merged[:symbols]).map(&:upcase)
        @poll_interval_sec = merged[:poll_interval_sec].to_i
        @max_risk_per_trade_pct = merged[:max_risk_per_trade_pct].to_f
        @max_open_trades = merged[:max_open_trades].to_i
        @max_setups_per_symbol = merged[:max_setups_per_symbol].to_i
        @model = merged[:model] || ENV.fetch('TRADING_AGENT_MODEL', nil) || ENV.fetch('OLLAMA_MODEL', nil)
        @initial_balance = merged[:initial_balance].to_f
        @slippage_pct = merged[:slippage_pct].to_f
        @taker_fee = merged[:taker_fee].to_f
        @maker_fee = merged[:maker_fee].to_f
        @telegram_notify = merged[:telegram_notify]
        @timeframes = merged[:timeframes]
        @verbose = ENV['TRADING_BOT_VERBOSE'] == 'true'
      end

      def paper?
        @mode == 'paper'
      end

      def live?
        @mode == 'live'
      end

      def verbose?
        @verbose
      end

      class << self
        def load(overrides = {})
          yaml_config = load_yaml
          env_config = load_env
          new(yaml_config.merge(env_config).merge(overrides))
        end

        private

        def load_yaml
          yaml_path = Rails.root.join('config/trading_bot.yml')
          return {} unless File.exist?(yaml_path)

          YAML.safe_load_file(yaml_path).deep_symbolize_keys
        rescue StandardError
          {}
        end

        def load_env
          {
            mode: ENV.fetch('TRADING_BOT_MODE', nil),
            symbols: ENV.fetch('TRADING_BOT_SYMBOLS', nil)&.split(',')&.map(&:strip),
            poll_interval_sec: ENV.fetch('TRADING_BOT_POLL_INTERVAL', nil)&.to_i,
            max_risk_per_trade_pct: ENV.fetch('TRADING_BOT_MAX_RISK_PCT', nil)&.to_f,
            max_open_trades: ENV.fetch('TRADING_BOT_MAX_OPEN_TRADES', nil)&.to_i,
            model: ENV.fetch('TRADING_AGENT_MODEL', nil) || ENV.fetch('OLLAMA_MODEL', nil),
            telegram_notify: ENV.fetch('TRADING_BOT_TELEGRAM_NOTIFY', nil) == 'true'
          }.compact
        end
      end
    end
  end
end
