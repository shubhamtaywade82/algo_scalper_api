# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::PublicIp' do
  describe 'GET /api/public_ip/audit' do
    it 'returns audit payload' do
      allow(Dhan::IpService).to receive(:audit_public_ips!).and_return(
        public_ipv4: '198.51.100.1',
        public_ipv6: 'None',
        registered_ips: { primary_ip: '198.51.100.1' }
      )

      get '/api/public_ip/audit'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['public_ipv4']).to eq('198.51.100.1')
    end
  end
end
