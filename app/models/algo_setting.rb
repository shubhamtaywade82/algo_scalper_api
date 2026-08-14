# frozen_string_literal: true

# Typed wrapper around the Setting model
# Provides schema definition, defaults, and easy typed access.
class AlgoSetting
  # Define all available settings in the system with their types, categories, and defaults
  SCHEMA = {
    # General / System
    'paper_trading_enabled' => { type: :boolean, default: true, category: 'General', description: 'Enable Paper Trading engine. Replaces real orders with simulated equivalents.' },
    'paper_balance' => { type: :integer, default: 100_000, category: 'General', description: 'Starting balance for paper trading accounts.' },

    # Time Restrictions (Loss Avoidance)
    'trading_time_restrictions_enabled' => { type: :boolean, default: false, category: 'Time Rules', description: 'Enable global blackout periods where no entries are taken.' },
    'trading_avoid_periods' => { type: :string, default: '10:00-12:30', category: 'Time Rules', description: 'Comma-separated list of HH:MM-HH:MM periods to block trades (IST).' },
    'trading_block_exits' => { type: :boolean, default: false, category: 'Time Rules', description: 'Block automated exits (trailing/SL/TP) during blackout periods.' },

    # Feature Flags
    'feature_enable_trend_scorer' => { type: :boolean, default: false, category: 'Features', description: 'Use new multi-indicator TrendScorer over basic Supertrend path.' },
    'feature_enable_peak_drawdown_activation' => { type: :boolean, default: false, category: 'Features', description: 'Activate trailing stops based on drawdown from peak premium.' },

    # Trend / Market Filters (ADX)
    'adx_threshold_nifty' => { type: :integer, default: 8, category: 'ADX Trend Filters', description: 'Minimum 1m ADX strength required to take NIFTY breakout entries.' },
    'adx_threshold_banknifty' => { type: :integer, default: 8, category: 'ADX Trend Filters', description: 'Minimum 1m ADX strength required to take BANKNIFTY breakout entries.' },
    'adx_threshold_sensex' => { type: :integer, default: 8, category: 'ADX Trend Filters', description: 'Minimum 1m ADX strength required to take SENSEX breakout entries.' },

    # Risk Global
    'risk_global_max_loss' => { type: :integer, default: -20_000, category: 'Risk Exits', description: 'Global hard stop loss limit for the entire day (rupees).' },
    'risk_global_daily_target' => { type: :integer, default: 50_000, category: 'Risk Exits', description: 'Global daily profit target to cease trading (rupees).' }
  }.freeze

  class << self
    def all_settings
      SCHEMA.map do |key, meta|
        {
          key: key,
          value: fetch(key),
          type: meta[:type],
          default: meta[:default],
          category: meta[:category],
          description: meta[:description]
        }
      end
    end

    def fetch(key)
      meta = SCHEMA[key]
      return nil unless meta

      case meta[:type]
      when :boolean
        Setting.fetch_bool(key, meta[:default])
      when :integer
        Setting.fetch_i(key, meta[:default])
      when :float
        Setting.fetch_f(key, meta[:default])
      else
        Setting.fetch(key, meta[:default])
      end
    end

    def put(key, value)
      meta = SCHEMA[key]
      return false unless meta

      # Parse typed value before saving as string
      val_to_save = case meta[:type]
                    when :boolean
                      ['1', 'true', 'yes', 'on', true].include?(value) ? 'true' : 'false'
                    when :integer
                      value.to_i.to_s
                    when :float
                      value.to_f.to_s
                    else
                      value.to_s
                    end

      Setting.put(key, val_to_save)
    end

    # Dynamic typed accessors
    # e.g., AlgoSetting.paper_trading_enabled?
    # e.g., AlgoSetting.paper_balance
    SCHEMA.each do |key, meta|
      if meta[:type] == :boolean
        define_method("#{key}?") { fetch(key) }
      else
        define_method(key) { fetch(key) }
      end
    end
  end
end
