# frozen_string_literal: true

module Dhan
  module Auth
    # Resolves the active authentication strategy based on DHAN_AUTH_MODE.
    #
    # Supported modes:
    #   totp       - Full automation via TOTP (default, recommended for production)
    #   manual     - Static ENV token (dev / fallback only)
    #   renew      - Renew an existing token via Dhan RenewToken API
    #   authority  - Optional external authority server (multi-service setups)
    #
    # Set via ENV:
    #   DHAN_AUTH_MODE=totp   # or manual | renew | authority
    class StrategyResolver
      STRATEGIES = {
        "authority" => -> { Strategies::Authority.new },
        "totp" => -> { Strategies::Totp.new },
        "manual" => -> { Strategies::Manual.new },
        "renew" => -> { Strategies::Renew.new }
      }.freeze

      # @return [Dhan::Auth::Strategies::Base] configured strategy instance
      def self.resolve
        mode = ENV.fetch("DHAN_AUTH_MODE", "totp").downcase.strip
        factory = STRATEGIES[mode]
        raise ArgumentError, "Unknown DHAN_AUTH_MODE: #{mode.inspect}. Valid: #{STRATEGIES.keys.join(', ')}" if factory.nil?

        factory.call
      end
    end
  end
end
