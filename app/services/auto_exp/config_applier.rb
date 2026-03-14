# frozen_string_literal: true

require "yaml"

module AutoExp
  class ConfigApplier
    CONFIG_PATH = Rails.root.join("config/strategy_config.yml")

    BOUNDS = {
      "entry.range_expansion_threshold" => 1.2..2.0,
      "entry.atr_rising_lookback" => 1..5,
      "strike_selection.delta_target" => 0.4..0.6,
      "exit.mfe_ratio_nifty" => 0.2..0.6,
      "exit.initial_stop" => 0.08..0.20,
      "risk.max_trades_per_day" => 1..5
    }.freeze

    def apply(parameter:, value:)
      config = YAML.load_file(CONFIG_PATH)

      section, key = parameter.split(".")

      value = clamp(parameter, value)

      config[section] ||= {}
      config[section][key] = value

      File.write(CONFIG_PATH, config.to_yaml)
    end

    private

    def clamp(param, value)
      range = BOUNDS[param]

      return value unless range

      [[value.to_f, range.min].max, range.max].min
    end
  end
end
