# frozen_string_literal: true

module Dhan
  module Auth
    # Resolves the active authentication strategy based on DHAN_AUTH_MODE.
    #
    # Supported modes:
    #   authority  - Delegate to external authority server (default, backward-compat)
    #   totp       - Full automation via TOTP one-time password
    #   manual     - Static ENV token (dev / fallback only)
    #   renew      - Renew an existing token via Dhan RenewToken API
    #
    # Set via ENV:
    #   DHAN_AUTH_MODE=totp   # or authority | manual | renew
    class StrategyResolver
      STRATEGIES = {
        "authority" => -> { Strategies::Authority.new },
        "totp"      => -> { Strategies::Totp.new },
        "manual"    => -> { Strategies::Manual.new },
        "renew"     => -> { Strategies::Renew.new }
      }.freeze

      # @return [Dhan::Auth::Strategies::Base] configured strategy instance
      def self.resolve
        mode = ENV.fetch("DHAN_AUTH_MODE", "authority").downcase.strip
        factory = STRATEGIES[mode]
        raise ArgumentError, "Unknown DHAN_AUTH_MODE: #{mode.inspect}. Valid: #{STRATEGIES.keys.join(', ')}" if factory.nil?

        factory.call
      end
    end
  end
end
