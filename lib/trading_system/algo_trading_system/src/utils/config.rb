# frozen_string_literal: true

require 'dry-configurable'
require 'yaml'

module Utils
  # Application configuration loaded from YAML
  class Config
    extend Dry::Configurable

    setting :capital, default: 500_000
    setting :risk_per_trade_pct, default: 1.0
    setting :max_daily_loss_pct, default: 3.0
    setting :max_positions, default: 3
    setting :broker, default: 'dhan'
    setting :symbols, default: %w[NIFTY BANKNIFTY FINNIFTY]
    setting :timeframe, default: '5m'

    class << self
      def load!(path = 'config/settings.yml')
        return unless File.exist?(path)

        yaml_data = YAML.load_file(path) || {}
        update(yaml_data)
      end

      def update(attributes)
        attributes.each do |key, value|
          config.send("#{key}=", value) if config.respond_to?("#{key}=")
        end
      end
    end
  end
end
