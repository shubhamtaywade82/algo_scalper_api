# frozen_string_literal: true

require 'json'
require 'open3'

module Utils
  # Wrapper to call the Node.js Greeks calculator
  class GreeksWrapper
    JS_PATH = File.join(File.dirname(__FILE__), 'greeks_calculator.js')

    def self.calculate(spot:, strike:, expiry_days:, iv_pct:, type: 'CALL', rate_pct: 6.0)
      cmd = "node #{JS_PATH} #{spot} #{strike} #{expiry_days} #{rate_pct} #{iv_pct} #{type}"
      stdout, stderr, status = Open3.capture3(cmd)

      if status.success?
        JSON.parse(stdout, symbolize_names: true)
      else
        Utils::Logger.error("greeks.calc_failed", error: stderr)
        nil
      end
    rescue StandardError => e
      Utils::Logger.error("greeks.wrapper_error", error: e.message)
      nil
    end
  end
end
