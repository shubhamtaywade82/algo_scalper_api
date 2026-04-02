# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- cross-cutting HTTP auth behavior (no single class)
RSpec.describe 'API token authentication' do
  describe 'dashboard tier (API_DASHBOARD_TOKEN)' do
    around do |example|
      previous = ENV.fetch('API_DASHBOARD_TOKEN', nil)
      ENV['API_DASHBOARD_TOKEN'] = 'dashboard-secret'
      example.run
    ensure
      if previous
        ENV['API_DASHBOARD_TOKEN'] = previous
      else
        ENV.delete('API_DASHBOARD_TOKEN')
      end
    end

    it 'returns 401 when Authorization is missing' do
      get '/api/health'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 when Bearer token matches' do
      get '/api/health', headers: { 'Authorization' => 'Bearer dashboard-secret' }
      expect(response).to have_http_status(:ok)
    end

    it 'accepts X-Api-Key as an alternative' do
      get '/api/health', headers: { 'X-Api-Key' => 'dashboard-secret' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'operator tier (API_OPERATOR_TOKEN)' do
    around do |example|
      previous = ENV.fetch('API_OPERATOR_TOKEN', nil)
      ENV['API_OPERATOR_TOKEN'] = 'operator-secret'
      example.run
    ensure
      if previous
        ENV['API_OPERATOR_TOKEN'] = previous
      else
        ENV.delete('API_OPERATOR_TOKEN')
      end
    end

    it 'returns 401 for public_ip audit without token' do
      get '/api/public_ip/audit'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 for public_ip audit with Bearer token' do
      allow(Dhan::IpService).to receive(:audit_public_ips!).and_return(
        public_ipv4: '198.51.100.1',
        public_ipv6: 'None',
        registered_ips: {}
      )

      get '/api/public_ip/audit', headers: { 'Authorization' => 'Bearer operator-secret' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'settings bulk in production' do
    it 'returns 503 when SETTINGS_UPDATE_TOKEN is unset' do
      allow(Rails.env).to receive(:production?).and_return(true)
      ENV.delete('SETTINGS_UPDATE_TOKEN')

      patch '/api/settings/bulk',
            params: { settings: { feature_flags: {} } },
            as: :json

      expect(response).to have_http_status(:service_unavailable)
      body = response.parsed_body
      expect(body['error']).to eq('settings_update_unconfigured')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
