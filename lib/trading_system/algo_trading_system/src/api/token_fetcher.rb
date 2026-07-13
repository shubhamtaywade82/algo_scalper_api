# frozen_string_literal: true

require 'faraday'
require 'json'
require 'dotenv'

module Api
  # Fetches Dhan access token from the remote auth server
  class TokenFetcher
    AUTH_URL = 'https://algo-trading-api.onrender.com/auth/dhan/token'

    def self.fetch_and_update_env(bearer_token: ENV.fetch('AUTH_SERVER_BEARER_TOKEN', nil))
      raise 'Missing AUTH_SERVER_BEARER_TOKEN' unless bearer_token

      response = Faraday.get(AUTH_URL) do |req|
        req.headers['Authorization'] = "Bearer #{bearer_token}"
      end

      unless response.success?
        raise "Failed to fetch token: #{response.status} - #{response.body}"
      end

      data = JSON.parse(response.body, symbolize_names: true)
      update_env_file(data)
      data
    end

    def self.update_env_file(data)
      env_path = '.env'
      content = File.exist?(env_path) ? File.read(env_path) : ''

      updates = {
        'DHAN_ACCESS_TOKEN' => data[:access_token],
        'DHAN_CLIENT_ID' => data[:client_id]
      }

      updates.each do |key, value|
        if content.match?(/^#{key}=/)
          content.gsub!(/^#{key}=.*$/, "#{key}=#{value}")
        else
          content += "\n#{key}=#{value}"
        end
      end

      File.write(env_path, content.strip + "\n")
      Dotenv.overload!(env_path)
    end
  end
end
