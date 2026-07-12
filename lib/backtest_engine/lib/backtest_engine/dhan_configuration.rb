module BacktestEngine
  module DhanConfiguration
    CLIENT_ID_ENV_KEY = "DHAN_CLIENT_ID"
    ACCESS_TOKEN_ENV_KEY = "DHAN_ACCESS_TOKEN"
    TOKEN_ENDPOINT_BASE_ENV_KEY = "DHAN_TOKEN_ENDPOINT_BASE_URL"
    TOKEN_ENDPOINT_BEARER_ENV_KEY = "DHAN_TOKEN_ENDPOINT_BEARER"

    module_function

    # Preferred: use ENV + access_token_provider (supports rotation)
    def configure_with_env_provider
      require "dhan_hq"

      DhanHQ.configure do |config|
        config.client_id = fetch_client_id
        config.access_token_provider = -> { fetch_access_token }
      end
    rescue LoadError
      warn "dhan_hq gem not available; DhanHQ will not be configured."
    end

    # Convenience: try existing config, then ENV+provider, then token endpoint.
    # Mirrors the snippet you shared.
    def configure_with_env_or_token_endpoint
      require "dhan_hq"

      DhanHQ.ensure_configuration!

      config = DhanHQ.configuration

      if blank?(config.access_token) && blank?(config.client_id)
        endpoint_base = ENV.fetch(TOKEN_ENDPOINT_BASE_ENV_KEY, nil)
        endpoint_bearer = ENV.fetch(TOKEN_ENDPOINT_BEARER_ENV_KEY, nil)

        if present?(endpoint_base) && present?(endpoint_bearer)
          DhanHQ.configure_from_token_endpoint(
            base_url: endpoint_base,
            bearer_token: endpoint_bearer
          )
        else
          configure_with_env_provider
        end
      end
    rescue LoadError
      warn "dhan_hq gem not available; DhanHQ will not be configured."
    end

    def fetch_client_id
      ENV.fetch(CLIENT_ID_ENV_KEY) do
        raise_missing_env!(CLIENT_ID_ENV_KEY)
      end
    end

    def fetch_access_token
      ENV.fetch(ACCESS_TOKEN_ENV_KEY) do
        raise_missing_env!(ACCESS_TOKEN_ENV_KEY)
      end
    end

    def blank?(value)
      value.respond_to?(:empty?) ? value.to_s.empty? : !value
    end

    def present?(value)
      !blank?(value)
    end

    def raise_missing_env!(key)
      raise KeyError, "ENV['#{key}'] is required to configure DhanHQ"
    end
    private_class_method :raise_missing_env!
  end
end

